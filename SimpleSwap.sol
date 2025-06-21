// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SimpleSwap is ERC20 {
    using Math for uint256;

    struct Pool {
        uint reserveA;
        uint reserveB;
        uint totalLiquidity;
    }

    
    mapping(bytes32 => Pool) public pools;
    

    constructor() ERC20("Liquidity Token", "LT") {}
    
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

        
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountASent);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBSent);

        
        p.reserveA       += amountASent;
        p.reserveB       += amountBSent;
        p.totalLiquidity += liquidity;
        
        _mint(to, liquidity);
        return (amountASent, amountBSent, liquidity);
    }
    



    function removeLiquidity(address tokenA, 
                            address tokenB, 
                            uint liquidity, 
                            uint amountAMin, 
                            uint amountBMin, 
                            address to, 
                            uint deadline) public returns (uint amountASent, uint amountBSent) {
    
            require(block.timestamp <= deadline, "Expired");
            require(balanceOf(msg.sender) >= liquidity, "LP low");
            bytes32 pairKey = _key(tokenA, tokenB);
            Pool storage p = pools[pairKey];
            
            
            amountASent = (liquidity * p.reserveA) / p.totalLiquidity;
            amountBSent = (liquidity * p.reserveB) / p.totalLiquidity;

            require(amountASent >= amountAMin, "Slippage A");
            require(amountBSent >= amountBMin, "Slippage B");

            
            p.reserveA -= amountASent;
            p.reserveB -= amountBSent;
            p.totalLiquidity -= liquidity;

            

            
            IERC20(tokenA).transfer(to, amountASent);
            IERC20(tokenB).transfer(to, amountBSent);
            _burn(msg.sender, liquidity);
            return (amountASent, amountBSent);
    }

    
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) public pure returns (uint amountOut) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "Bad inputs");
        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn); // sin fee
    }

    function getPrice(address tokenA, address tokenB)
        external view returns (uint price)
    {
        bytes32 k = _key(tokenA, tokenB);
        Pool storage p = pools[k];
        require(p.reserveA > 0 && p.reserveB > 0, "No reserves");

        price = (p.reserveB * 1e18) / p.reserveA;
    }

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

        
        uint reserveIn  = p.reserveA;
        uint reserveOut = p.reserveB;

        uint amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Slippage");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[1]).transfer(to, amountOut);

        p.reserveA  += amountIn;
        p.reserveB -= amountOut;
    
        
    }
}