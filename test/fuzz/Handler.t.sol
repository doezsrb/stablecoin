//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Script.sol";
import {SCEngine} from "../../src/SCEngine.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    SCEngine scEngine;
    StableCoin sc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 public callingMint;
    address[] addressWithCollateral;
    MockV3Aggregator ethSeedPriceMock;

    constructor(SCEngine _scEngine, StableCoin _sc) {
        scEngine = _scEngine;
        sc = _sc;
        address[] memory collateralTokens = scEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethSeedPriceMock = MockV3Aggregator(scEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function updateCollateralPrice(uint96 newPrice) public {
        int256 newPriceInt = int256(uint256(newPrice));
        ethSeedPriceMock.updateAnswer(newPriceInt);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralSeed(collateralSeed);
        amount = bound(amount, 1, type(uint96).max);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(scEngine), amount);
        scEngine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        addressWithCollateral.push(msg.sender);
    }

    function mintSc(uint256 amount, uint256 addressSeed) public {
        if (addressWithCollateral.length == 0) {
            return;
        }
        address sender = addressWithCollateral[addressSeed % addressWithCollateral.length];
        (uint256 totalScMinted, uint256 collaterValueInUsd) = scEngine.getAccountInformation(sender);
        int256 maxSctoMint = (int256(collaterValueInUsd) / 2) - int256(totalScMinted);
        if (maxSctoMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxSctoMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        scEngine.mintSc(amount);
        vm.startPrank(sender);
        callingMint++;
    }

    function reedemCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = ERC20Mock(_getCollateralSeed(collateralSeed));
        uint256 maxCollateralToReedem = scEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amount = bound(amount, 0, maxCollateralToReedem);
        console.log(maxCollateralToReedem);
        if (amount == 0 || maxCollateralToReedem == 0) {
            return;
        }

        scEngine.redeemCollateral(address(collateral), amount);
    }

    function _getCollateralSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
