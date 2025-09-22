// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUSDFEarn {
    function deposit(uint256 amountIn) external;
    function USDT() external view returns (IERC20);
    function USDF() external view returns (IERC20);
}
