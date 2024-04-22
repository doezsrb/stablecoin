//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Script.sol";
import {DeploySc} from "../script/DeploySc.s.sol";
import {SCEngine} from "../src/SCEngine.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract SCEngineTest is Test {
    DeploySc deployer;
    StableCoin sc;
    SCEngine scEngine;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address public USER = makeAddr("test");
    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 public constant STARTING_TOKEN_BALANCE = 1 ether;

    function setUp() public {
        deployer = new DeploySc();
        (sc, scEngine, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetwork();
        ERC20Mock(weth).mint(USER, STARTING_TOKEN_BALANCE);
    }

    function testGetUsdValue() public view {
        uint256 expectedUsd = 4000e18;
        uint256 ethAmount = 2e18;
        uint256 actualUsd = scEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testDepositRevertsIfZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(scEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(SCEngine.SCEngine__AmountMustBeMoreThanZero.selector);
        scEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    modifier setUserDeposit() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(scEngine), AMOUNT_COLLATERAL);
        scEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        _;
    }

    function testDepositAndGetInformation() public setUserDeposit {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = scEngine.getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralValueInUsd = 160 ether;
        assertEq(expectedDscMinted, totalDscMinted);
        assertEq(expectedCollateralValueInUsd, collateralValueInUsd);
    }

    function testMint() public setUserDeposit {
        scEngine.mintSc(40 ether);
        uint256 expectedMintedSc = 40 ether;
        (uint256 totalScMinted,) = scEngine.getAccountInformation(USER);
        assertEq(expectedMintedSc, totalScMinted);
    }

    function testHealthFactorRevert() public setUserDeposit {
        vm.expectRevert(SCEngine.SCEngine__BreaksHealthFactor.selector);
        scEngine.mintSc(81 ether);
    }

    function testGetAccountCollateralValue() public setUserDeposit {
        uint256 expected = 160 ether;
        uint256 res = scEngine.getAccountCollateralValue(USER);
        assertEq(expected, res);
    }

    function testConvertScToCollateralValue() public view {
        uint256 expected = 20;
        uint256 actual = scEngine.getCollateralValueFromMintedToken(weth, 20 ether);
        console.log(actual);
        assertEq(expected, actual);
    }

    modifier setUserDepositAndMint() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(scEngine), AMOUNT_COLLATERAL);

        scEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(scEngine), 10 ether);

        scEngine.mintSc(10 ether);

        _;
    }

    function testRedeemAndBurn() public setUserDepositAndMint {
        uint256 expectedSc = 0;
        uint256 expectedCollateral = 0;

        vm.startPrank(USER);
        sc.approve(address(scEngine), 10 ether);
        scEngine.redeemCollateralForSc(weth, AMOUNT_COLLATERAL, 10 ether);

        (uint256 totalScMinted, uint256 collateralValueInUsd) = scEngine.getAccountInformation(USER);

        assertEq(expectedSc, totalScMinted);
        assertEq(expectedCollateral, collateralValueInUsd);
    }

    address USER1 = makeAddr("OK_USER");
    address TRY_LIQUIDATE_USER = makeAddr("TRY_LIQUIDATE_USER");

    modifier setOkUserDepositAndMint() {
        ERC20Mock(weth).mint(USER1, AMOUNT_COLLATERAL);
        ERC20Mock(weth).mint(TRY_LIQUIDATE_USER, AMOUNT_COLLATERAL + 1 ether);

        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(scEngine), AMOUNT_COLLATERAL);
        scEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        scEngine.mintSc(900 ether);
        vm.stopPrank();
        vm.startPrank(TRY_LIQUIDATE_USER);
        ERC20Mock(weth).approve(address(scEngine), AMOUNT_COLLATERAL + 1 ether);
        scEngine.depositCollateral(weth, AMOUNT_COLLATERAL + 1 ether);
        vm.stopPrank();
        _;
    }

    /* function testLiquidateShouldRevertWithOkUser() public setOkUserDepositAndMint {
        vm.startPrank(TRY_LIQUIDATE_USER);
        vm.expectRevert(SCEngine.SCEngine__HealthFactorOk.selector);
        scEngine.liquidate(weth, USER1, 900 ether);
        vm.stopPrank();
    } */

    function testLiquidate() public setOkUserDepositAndMint {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8);
        vm.startPrank(TRY_LIQUIDATE_USER);
        scEngine.liquidate(weth, USER1, 900 ether);
        vm.stopPrank();
        uint256 user1Tokens = scEngine.getUserScMinted(USER1);
        console.log("TRY LIQUIDATE USER COLLATERAL: ", scEngine.getCollateralBalanceOfUser(TRY_LIQUIDATE_USER, weth));
        assertEq(user1Tokens, 0);
    }
}
