// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";


contract asUSDF is AccessControl, ERC20Pausable, ERC20Permit {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_AND_BURN_ROLE = keccak256("MINTER_AND_BURN_ROLE");

    constructor(
        string memory _name,
        string memory _symbol,
        address _defaultAdmin,
        address _timelockAddress
    ) ERC20(_name, _symbol)  ERC20Permit(_name){
        _grantRole(DEFAULT_ADMIN_ROLE, _timelockAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(ADMIN_ROLE, _defaultAdmin);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_AND_BURN_ROLE) {
        require(amount > 0, "ERC20: mint zero amount");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(MINTER_AND_BURN_ROLE) {
        require(amount > 0, "ERC20: burn zero amount");
        _burn(from, amount);
    }

    function _update(address from, address to, uint256 value) internal virtual override(ERC20, ERC20Pausable) {
        ERC20Pausable._update(from, to, value);
    }
}
