// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract SimpleSwap {
    using Math for uint256;

    struct Pool {
        uint reserveA;
        uint reserveB;
        uint totalLiquidity;
    }

    
    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => mapping(address => uint)) public lpBalance;

    
    function _key(address tokenA, address tokenB) internal pure returns (bytes32) {  
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);   
        return keccak256(abi.encodePacked(t0, t1)); 
    }

    

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public returns (uint amountASent, uint amountBSent, uint liquidity)
    {
        require(block.timestamp <= deadline, "Expired");
        bytes32 pairKey = _key(tokenA, tokenB);

        Pool storage p = pools[pairKey];

        
        if (p.totalLiquidity == 0) {
            amountASent   = amountADesired;
            amountBSent   = amountBDesired;
            liquidity = Math.sqrt(amountASent * amountBSent);
        } else {
            
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

        
        IERC20(tokenA).transferFrom(msg.sender, to, amountASent);
        IERC20(tokenB).transferFrom(msg.sender, to, amountBSent);

        
        p.reserveA       += amountASent;
        p.reserveB       += amountBSent;
        p.totalLiquidity += liquidity;
        lpBalance[pairKey][msg.sender] += liquidity;

        return (amountASent, amountBSent, liquidity);
    }
    /**
    * @dev Wrapper function to allow deadline as ttl in seconds
    */

    function addLiquidityWithTtl(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint ttlSeconds
        ) external returns (uint amountA, uint amountB, uint liquidity) {
            uint deadline = block.timestamp + ttlSeconds;
            return addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, to, deadline);
    }



    function removeLiquidity(address tokenA, 
                            address tokenB, 
                            uint liquidity, 
                            uint amountAMin, 
                            uint amountBMin, 
                            address to, 
                            uint deadline) public returns (uint amountASent, uint amountBSent) {
    
            require(block.timestamp <= deadline, "Expired");

            bytes32 pairKey = _key(tokenA, tokenB);
            Pool storage p = pools[pairKey];
            require(lpBalance[pairKey][msg.sender] >= liquidity, "Not enough LP tokens");

            
            amountASent = (liquidity * p.reserveA) / p.totalLiquidity;
            amountBSent = (liquidity * p.reserveB) / p.totalLiquidity;

            require(amountASent >= amountAMin, "Slippage A");
            require(amountBSent >= amountBMin, "Slippage B");

            
            p.reserveA -= amountASent;
            p.reserveB -= amountBSent;
            p.totalLiquidity -= liquidity;

            
            lpBalance[pairKey][msg.sender] -= liquidity;

            
            IERC20(tokenA).transfer(to, amountASent);
            IERC20(tokenB).transfer(to, amountBSent);

            return (amountASent, amountBSent);
    }

    /**
    * @dev Wrapper function to allow deadline as ttl in seconds
    */
    function removeLiquidityWithTtl(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint ttlSeconds
        ) external returns (uint amountASent, uint amountBSent) {
            uint deadline = block.timestamp + ttlSeconds;
            return removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

}