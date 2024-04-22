//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract StableCoin is ERC20Burnable, Ownable {
    error StableCoin__AmountIsZero();
    error StableCoin__AmountExceedsBalance();
    error StableCoin__AddressIsZero();

    constructor() ERC20("StableCoin", "STC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableCoin__AmountIsZero();
        }
        if (balance < _amount) {
            revert StableCoin__AmountExceedsBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCoin__AddressIsZero();
        }
        if (_amount <= 0) {
            revert StableCoin__AmountIsZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
