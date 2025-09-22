// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20WithPermit is IERC20, IERC20Permit {
    function permit(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
