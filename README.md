# SimpleSwap – Functional Specification (English)

## Objective
Implement an on-chain Automated Market Maker named **SimpleSwap** that

* lets users add and remove liquidity for a pair of ERC-20 tokens,
* performs token-for-token swaps with the constant-product formula (no external protocol),
* exposes helper views to query pool price and deterministic swap output.

The contract does **not** depend on Uniswap V2 code or its fee logic; it is a concise re-implementation for academic purposes.

---

## Public Interface

| Function | Solidity signature (0.8.30) |
|----------|-----------------------------|
| **Add liquidity** | `addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity)` |
| **Remove liquidity** | `removeLiquidity(address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB)` |
| **Swap exact tokens** | `swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts)` |
| **Get spot price** | `getPrice(address tokenA, address tokenB) external view returns (uint price)` |
| **Get deterministic output** | `getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut)` |

---

### 1. `addLiquidity`

Transfers the caller’s tokens into the pool and mints Liquidity-Token (LT) to `to`.

**Inputs**

* `tokenA`, `tokenB` – token addresses  
* `amountADesired`, `amountBDesired` – amounts the user wishes to deposit  
* `amountAMin`, `amountBMin` – slippage guards  
* `to` – LT recipient  
* `deadline` – unix time limit

**Tasks**

1. Order tokens (smaller address first) and fetch/create pool.  
2. If pool empty, accept desired amounts and mint `sqrt(A × B)` LT.  
3. Otherwise, compute optimal counter-amount to keep `reserveA / reserveB` constant.  
4. Pull final amounts from caller.  
5. Update reserves and `totalLiquidity`.  
6. Mint LT to `to`.

**Returns**

* `amountA`, `amountB` – actual tokens deposited  
* `liquidity` – LT minted

---

### 2. `removeLiquidity`

Burns caller’s LT and refunds proportional reserves.

**Inputs**

* `tokenA`, `tokenB` – token addresses  
* `liquidity` – LT to burn  
* `amountAMin`, `amountBMin` – slippage guards  
* `to` – recipient of tokens  
* `deadline` – time limit

**Tasks**

1. Verify caller balance ≥ `liquidity`.  
2. Calculate share: `liquidity / totalLiquidity`.  
3. Burn LT, update reserves.  
4. Transfer `amountA`, `amountB` to `to`.

**Returns**

* `amountA`, `amountB` withdrawn

---

### 3. `swapExactTokensForTokens`

Swaps an exact `amountIn` of `path[0]` for as many `path[1]` tokens as possible.

**Inputs**

* `amountIn` – exact tokens provided  
* `amountOutMin` – minimum acceptable output  
* `path` – `[tokenIn, tokenOut]`  
* `to` – recipient of output tokens  
* `deadline` – time limit

**Tasks**

1. Fetch current reserves.  
2. Compute `amountOut = amountIn · reserveOut / (reserveIn + amountIn)` (zero fee).  
3. Revert if `amountOut < amountOutMin`.  
4. Pull `amountIn`, send `amountOut`, update reserves.

**Returns**

* `amounts` – dynamic array `[amountIn, amountOut]`

---

### 4. `getPrice`

Spot price of `tokenA` denominated in `tokenB`, scaled to 18 decimals.

---

### 5. `getAmountOut`

Pure helper that returns the deterministic output for a swap, given `amountIn`, `reserveIn`, `reserveOut`.

`amountOut = amountIn · reserveOut / (reserveIn + amountIn)`

---

## Pool Storage Key

`pairKey = keccak256(min(tokenA, tokenB), max(tokenA, tokenB))`

```solidity
struct Pool {
    uint reserveA;          // token with smaller address
    uint reserveB;          // token with larger  address
    uint totalLiquidity;    // total LT minted
}
mapping(bytes32 => Pool) public pools;
