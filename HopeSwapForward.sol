// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amt) external returns (bool);
    function approve(address spender, uint256 amt) external returns (bool);
    function transfer(address to, uint256 amt) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

interface IPancakeRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract HopeSwapForward {
    IERC20 public immutable usdt;
    IERC20 public immutable hope;
    IERC20 public immutable wbnb;
    IPancakeRouter public immutable router;
    address public immutable owner;

    event Swapped(uint256 inAmt, uint256 outAmt);

    constructor(
        address _router,
        address _usdt,
        address _hope,
        address _wbnb
    ) {
        require(_router != address(0) && _usdt != address(0) && _hope != address(0) && _wbnb != address(0), "Zero address not allowed");
        router = IPancakeRouter(_router);
        usdt   = IERC20(_usdt);
        hope   = IERC20(_hope);
        wbnb   = IERC20(_wbnb);
        owner  = msg.sender;
    }

    function swapThenForward(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external {
        require(amountIn > 0, "Zero amountIn");
        require(deadline >= block.timestamp, "Deadline passed");

        // Pull USDT from sender
        require(usdt.transferFrom(msg.sender, address(this), amountIn), "USDT transferFrom failed");

        // Approve router to spend USDT
        require(usdt.approve(address(router), amountIn), "USDT approve failed");

        // Path: USDT → WBNB → HOPE
        address[] memory path = new address[](3);
        path[0] = address(usdt);
        path[1] = address(wbnb);
        path[2] = address(hope);

        // Perform the swap
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );

        uint256 outAmt = hope.balanceOf(address(this));
        require(outAmt > 0, "No output tokens received");

        // Forward HOPE to owner
        require(hope.transfer(owner, outAmt), "HOPE transfer failed");

        emit Swapped(amountIn, outAmt);
    }
}