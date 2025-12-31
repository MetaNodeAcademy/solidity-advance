// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./SSToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title Stakee
 * @notice 质押合约：
 */
contract Stakee is Initializable, PausableUpgradeable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function initialize() public initializer {
        __Pausable_init();
        __UUPSUpgradeable_init();
        __AccessControl_init();

        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    /**
     * @notice 授权升级
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice 暂停合约
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice 恢复合约
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
