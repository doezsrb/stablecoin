//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {StableCoin} from "../src/StableCoin.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/Script.sol";

contract SCEngine is ReentrancyGuard {
    error SCEngine__AmountMustBeMoreThanZero();
    error SCEngine__NotAllowedToken();
    error SCEngine__TransferFailed();
    error SCEngine__MintFailed();

    error SCEngine__BreaksHealthFactor();

    error SCEngine__HealthFactorOk();
    error SCEngine__HealthFactorNotImproved();

    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;

    address[] private s_collateralTokens;
    StableCoin private immutable i_sc;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountScMinted) private s_ScMinted;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed from, address indexed to, address indexed tokenCollateralAddress, uint256 amountCollateral
    );

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert SCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert SCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address scAddress) {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_sc = StableCoin(scAddress);
    }

    function depositCollateralAndMintSc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountScToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintSc(amountScToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert SCEngine__TransferFailed();
        }
    }

    function redeemCollateralForSc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountSc)
        external
    {
        burnSc(amountSc);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
        moreThanZero(amountCollateral)
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert SCEngine__TransferFailed();
        }
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintSc(uint256 amountScToMint) public moreThanZero(amountScToMint) nonReentrant {
        s_ScMinted[msg.sender] += amountScToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_sc.mint(msg.sender, amountScToMint);
        if (!minted) {
            revert SCEngine__MintFailed();
        }
    }

    function _burnSc(uint256 amount, address onBehalfOf, address scFrom) private {
        s_ScMinted[onBehalfOf] -= amount;
        i_sc.transferFrom(scFrom, address(this), amount);
        i_sc.burn(amount);
    }

    function burnSc(uint256 amount) public moreThanZero(amount) {
        _burnSc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert SCEngine__HealthFactorOk();
        }

        uint256 collateralFromDebtCovered = getCollateralValueFromMintedToken(tokenCollateralAddress, debtToCover);

        uint256 bonusCollateral = (collateralFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = collateralFromDebtCovered + bonusCollateral;
        _redeemCollateral(tokenCollateralAddress, totalCollateralToRedeem, user, msg.sender);
        _burnSc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert SCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getCollateralValueFromMintedToken(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface agv3 = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = agv3.latestRoundData();

        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function calculateHealthFactor(uint256 totalScMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalScMinted, collateralValueInUsd);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getUsdValue(address token, uint256 amount) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function _getUsdValue(address token, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface agv3 = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = agv3.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalScMinted, uint256 collaterValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalScMinted, uint256 collaterValueInUsd)
    {
        totalScMinted = s_ScMinted[user];
        collaterValueInUsd = getAccountCollateralValue(user);
    }

    function _calculateHealthFactor(uint256 totalScMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalScMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalScMinted;
    }

    function _healthFactor(address user) public view returns (uint256) {
        (uint256 totalScMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalScMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert SCEngine__BreaksHealthFactor();
        }
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_sc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getUserScMinted(address user) external view returns (uint256) {
        return s_ScMinted[user];
    }
}
