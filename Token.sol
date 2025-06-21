// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";


contract Token is ERC20, ERC20Burnable {
    constructor(string memory name, string memory sym)
        ERC20(name, sym)
       
    {
        _mint(msg.sender, 1_000_000);
    }

    function mint(address to, uint256 amount) public  {
        _mint(to, amount);
    }
}