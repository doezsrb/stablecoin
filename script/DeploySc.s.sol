//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {SCEngine} from "../src/SCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeploySc is Script {
    address[] public tokenAdresses;
    address[] public feedPriceAddresses;

    function run() external returns (StableCoin, SCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetwork();
        tokenAdresses = [weth, wbtc];
        feedPriceAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.startBroadcast(deployerKey);
        StableCoin sc = new StableCoin();
        SCEngine scEngine = new SCEngine(tokenAdresses, feedPriceAddresses, address(sc));

        sc.transferOwnership(address(scEngine));
        vm.stopBroadcast();
        return (sc, scEngine, config);
    }
}
