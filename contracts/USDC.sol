// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20 {
    uint8 private immutable _decimals;
    uint8 private version = 1;

    constructor() ERC20("USDC", "USDC") {
        _decimals = 6;
        _mint(msg.sender, 5000000 * 10**6);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
