// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// mock class using ERC20
contract ERC20MockDecimals is ERC20 {
    uint8 _decimals;
    constructor (
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance,
        uint8 decimals
    ) payable ERC20(name, symbol) {
        _decimals = decimals;
        //_setupDecimals(decimals);
        _mint(initialAccount, initialBalance);
    }

    function mint(address account) public {
        _mint(account, 1000e18);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function transferInternal(address from, address to, uint256 value) public {
        _transfer(from, to, value);
    }

    function approveInternal(address owner, address spender, uint256 value) public {
        _approve(owner, spender, value);
    }
}