// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title  SimpleSwap
 * @notice Minimal AMM (Uniswap-V2–style, no fee) that lets users
 *         – add / remove liquidity for a token pair,
 *         – swap an exact amount of one token for the other,
 *         – query pool price and deterministic amount-out.
 *
 *         Liquidity positions are represented by an ERC-20 token
 *         named **Liquidity Token (LT)** that can be freely transferred.
 */
contract SimpleSwap is ERC20 {
    using Math for uint256;

    /* ────────────────────────────────────────────────────────────
                                STORAGE
       ────────────────────────────────────────────────────────── */

    /**
     * @dev Structure holding the state of a single token pair.
     *
     * `reserveA` and `reserveB` **always** correspond to the tokens
     * with the lexicographically smaller / greater address once the
     * pair key is built in `_key()`.
     */
    struct Pool {
        uint reserveA;        ///< current reserve of the smaller‐address token
        uint reserveB;        ///< current reserve of the larger‐address  token
        uint totalLiquidity;  ///< total LT minted for this pair
    }

    /// @notice Mapping from `keccak256(token0, token1)` to pool data
    mapping(bytes32 => Pool) public pools;

    /* ────────────────────────────────────────────────────────────
                               CONSTRUCTOR
       ────────────────────────────────────────────────────────── */

    /**
     * @dev Deploy the LP ERC-20.
     *      Name / symbol follow the assignment requirement.
     */
    constructor() ERC20("Liquidity Token", "LT") {}

    /* ────────────────────────────────────────────────────────────
                            INTERNAL HELPERS
       ────────────────────────────────────────────────────────── */

    /**
     * @notice Build the unique key for a token pair.
     * @dev    Tokens are ordered so `tokenA < tokenB`.
     * @param  tokenA First token address supplied by user
     * @param  tokenB Second token address supplied by user
     * @return key    Hash used as mapping key
     */
    function _key(address tokenA, address tokenB)
        internal
        pure
        returns (bytes32 key)
    {
        (address t0, address t1) =
            tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        key = keccak256(abi.encodePacked(t0, t1));
    }

    /* ────────────────────────────────────────────────────────────
                           ADD   LIQUIDITY
       ────────────────────────────────────────────────────────── */

    /**
     * @notice Add liquidity to an empty or existing pool.
     * @param tokenA         Address of token A
     * @param tokenB         Address of token B
     * @param amountADesired Amount of token A the user wants to deposit
     * @param amountBDesired Amount of token B the user wants to deposit
     * @param amountAMin     Minimum acceptable amount A (slippage guard)
     * @param amountBMin     Minimum acceptable amount B (slippage guard)
     * @param to             Recipient of the newly minted LT
     * @param deadline       Unix timestamp after which the tx is invalid
     * @return amountASent   Final amount A deposited
     * @return amountBSent   Final amount B deposited
     * @return liquidity     LT tokens minted
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    )
        public
        returns (uint amountASent, uint amountBSent, uint liquidity)
    {
        require(block.timestamp <= deadline, "Expired");
        bytes32 pairKey = _key(tokenA, tokenB);
        Pool storage p  = pools[pairKey];

        /* ―― first liquidity provider ―― */
        if (p.totalLiquidity == 0) {
            amountASent = amountADesired;
            amountBSent = amountBDesired;
            liquidity   = Math.sqrt(amountASent * amountBSent);
        } else {
            /* ―― subsequent providers keep price ratio invariant ―― */
            uint amountBOptimal = (amountADesired * p.reserveB) / p.reserveA;

            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Slippage B");
                amountASent = amountADesired;
                amountBSent = amountBOptimal;
            } else {
                uint amountAOptimal = (amountBDesired * p.reserveA) / p.reserveB;
                require(amountAOptimal >= amountAMin, "Slippage A");
                amountASent = amountAOptimal;
                amountBSent = amountBDesired;
            }

            liquidity = Math.min(
                (amountASent * p.totalLiquidity) / p.reserveA,
                (amountBSent * p.totalLiquidity) / p.reserveB
            );
        }
        require(liquidity > 0, "LIQ=0");

        /* ―― move tokens into the pool ―― */
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountASent);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBSent);

        /* ―― update pool reserves ―― */
        p.reserveA       += amountASent;
        p.reserveB       += amountBSent;
        p.totalLiquidity += liquidity;

        /* ―― mint LP tokens ―― */
        _mint(to, liquidity);

        return (amountASent, amountBSent, liquidity);
    }

    /* ────────────────────────────────────────────────────────────
                          REMOVE   LIQUIDITY
       ────────────────────────────────────────────────────────── */

    /**
     * @notice Burn LT and withdraw the underlying tokens.
     * @param  tokenA      Address of token A
     * @param  tokenB      Address of token B
     * @param  liquidity   Amount of LT to burn
     * @param  amountAMin  Minimum token A to receive
     * @param  amountBMin  Minimum token B to receive
     * @param  to          Recipient of tokens A & B
     * @param  deadline    Timestamp after which tx is invalid
     * @return amountASent Amount A withdrawn
     * @return amountBSent Amount B withdrawn
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public returns (uint amountASent, uint amountBSent) {
        require(block.timestamp <= deadline, "Expired");
        require(balanceOf(msg.sender) >= liquidity, "LP low");

        bytes32 pairKey = _key(tokenA, tokenB);
        Pool storage p  = pools[pairKey];

        /* proportional amounts to withdraw */
        amountASent = (liquidity * p.reserveA) / p.totalLiquidity;
        amountBSent = (liquidity * p.reserveB) / p.totalLiquidity;

        require(amountASent >= amountAMin, "Slippage A");
        require(amountBSent >= amountBMin, "Slippage B");

        /* update pool */
        p.reserveA       -= amountASent;
        p.reserveB       -= amountBSent;
        p.totalLiquidity -= liquidity;

        _burn(msg.sender, liquidity);                 // burn LT

        /* transfer underlying tokens */
        IERC20(tokenA).transfer(to, amountASent);
        IERC20(tokenB).transfer(to, amountBSent);

        return (amountASent, amountBSent);
    }

    /* ────────────────────────────────────────────────────────────
                     PURE HELPER: getAmountOut
       ────────────────────────────────────────────────────────── */

    /**
     * @notice Deterministic output amount for a given input,
     *         preserving the constant-product invariant `x*y=k`.
     * @param  amountIn    Exact tokens sent to the pool
     * @param  reserveIn   Current reserve of the input token
     * @param  reserveOut  Current reserve of the output token
     * @return amountOut   Tokens that will be received
     */
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) public pure returns (uint amountOut) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "Bad inputs");
        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    /* ────────────────────────────────────────────────────────────
                               PRICE VIEW
       ────────────────────────────────────────────────────────── */

    /**
     * @notice Spot price of `tokenA` denominated in `tokenB`.
     * @dev    Returned with 18 decimals of precision.
     */
    function getPrice(address tokenA, address tokenB)
        external
        view
        returns (uint price)
    {
        bytes32 k  = _key(tokenA, tokenB);
        Pool storage p = pools[k];
        require(p.reserveA > 0 && p.reserveB > 0, "No reserves");

        price = (p.reserveB * 1e18) / p.reserveA; // A in terms of B
    }

    /* ────────────────────────────────────────────────────────────
                              SWAP EXACT
       ────────────────────────────────────────────────────────── */

    /**
     * @notice Swap an exact `amountIn` of `path[0]` for as many `path[1]`
     *         tokens as possible, enforcing `amountOutMin` as slippage guard.
     * @param  amountIn       Exact tokens provided
     * @param  amountOutMin   Minimum acceptable tokens to receive
     * @param  path           Ordered array [tokenIn, tokenOut]
     * @param  to             Recipient of the output tokens
     * @param  deadline       Timestamp limit for tx validity
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external {
        require(block.timestamp <= deadline, "Expired");
        require(path.length == 2 && amountIn > 0, "Bad params");

        bytes32 k = _key(path[0], path[1]);
        Pool storage p = pools[k];
        require(p.totalLiquidity > 0, "Pool empty");

        /* current reserves (tokenA < tokenB) */
        uint reserveIn  = p.reserveA;
        uint reserveOut = p.reserveB;

        uint amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Slippage");

        /* token transfers */
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[1]).transfer(to, amountOut);

        /* update reserves */
        p.reserveA += amountIn;
        p.reserveB -= amountOut;

        
    }
}
