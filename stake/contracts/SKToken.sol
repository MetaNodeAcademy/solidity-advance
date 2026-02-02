// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SKToken
 * @author Jss
 * @notice 质押代币合约
 */
contract SKToken is ERC20, Ownable {
    constructor() ERC20("Stakeoken", "SKT") Ownable(msg.sender) {
        _mint(msg.sender, 10 ** 8);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}
