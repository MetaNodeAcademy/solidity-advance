// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract PositionManager is ERC721 {
    constructor() ERC721("PositionManager", "PM") {
        _mint(msg.sender, 1);
    }
}
