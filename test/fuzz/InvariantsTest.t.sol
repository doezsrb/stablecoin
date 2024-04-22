//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {console} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeploySc} from "../../script/DeploySc.s.sol";
import {SCEngine} from "../../src/SCEngine.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "../fuzz/Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeploySc deployer;
    SCEngine scEngine;
    StableCoin sc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeploySc();

        (sc, scEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetwork();
        handler = new Handler(scEngine, sc);
        targetContract(address(handler));
    }

    function invariant_protocolMushHaveMoreValueTHanTotalSuply() public view {
        uint256 totalSupply = sc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(scEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(scEngine));

        uint256 wethValue = scEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = scEngine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
