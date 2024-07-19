// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "../src/UniswapV2FactoryClone.sol";
import "../src/UniswapV2PairClone.sol";
import "solady/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function name() public pure override returns (string memory) {
        return "Mock Token";
    }

    function symbol() public pure override returns (string memory) {
        return "MOCK";
    }
}

contract UniswapV2Test is Test {
    UniswapV2FactoryClone factory;
    MockERC20 tokenA;
    MockERC20 tokenB;
    address feeToSetter;
    UniswapV2Pair pair;

    function setUp() public {
        feeToSetter = address(this);
        factory = new UniswapV2FactoryClone(feeToSetter);
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");

        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = UniswapV2Pair(pairAddress);

        // Add initial liquidity
        tokenA.transfer(address(pair), 10000 * 10 ** 18);
        tokenB.transfer(address(pair), 10000 * 10 ** 18);
        pair.mint(address(this));
    }

    function testCreatePair() public {
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pairAddress);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pairAddress);
    }

    function testCannotCreateExistingPair() public {
        vm.expectRevert("UniswapV2: PAIR_EXISTS");
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testCannotCreatePairWithZeroAddress() public {
        vm.expectRevert("UniswapV2: ZERO_ADDRESS");
        factory.createPair(address(tokenA), address(0));
    }

    function testSetFeeTo() public {
        address newFeeTo = address(0x123);
        factory.setFeeTo(newFeeTo);
        assertEq(factory.feeTo(), newFeeTo);
    }

    function testCannotSetFeeToUnauthorized() public {
        vm.prank(address(0x456));
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeTo(address(0x123));
    }

    function testSetFeeToSetter() public {
        address newFeeToSetter = address(0x789);
        factory.setFeeToSetter(newFeeToSetter);
        assertEq(factory.feeToSetter(), newFeeToSetter);
    }

    function testCannotSetFeeToSetterUnauthorized() public {
        vm.prank(address(0x456));
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeToSetter(address(0x789));
    }

    function testMintLiquidity() public {
        vm.startPrank(address(this));
        uint256 amountA = 1000 * 10 ** 18;
        uint256 amountB = 1000 * 10 ** 18;

        tokenA.transfer(address(pair), amountA);
        tokenB.transfer(address(pair), amountB);

        pair.mint(address(this));

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(reserve0, 11000 * 10 ** 18);
        assertEq(reserve1, 11000 * 10 ** 18);
        vm.stopPrank();
    }

    function testBurnLiquidity() public {
        vm.startPrank(address(this));

        // Record initial balances and reserves
        uint256 initialBalanceA = tokenA.balanceOf(address(this));
        uint256 initialBalanceB = tokenB.balanceOf(address(this));
        (uint112 oldReserves0, uint112 oldReserves1,) = pair.getReserves();

        // Add liquidity
        uint256 amountA = 1000 * 10 ** 18;
        uint256 amountB = 1000 * 10 ** 18;
        tokenA.transfer(address(pair), amountA);
        tokenB.transfer(address(pair), amountB);
        pair.mint(address(this));

        // Burn all liquidity
        uint256 liquidity = pair.balanceOf(address(this));
        pair.transfer(address(pair), liquidity);
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));

        // Check final balances and reserves
        (uint112 newReserves0, uint112 newReserves1,) = pair.getReserves();
        uint256 finalBalanceA = tokenA.balanceOf(address(this));
        uint256 finalBalanceB = tokenB.balanceOf(address(this));
        // Assert that reserves have decreased
        assert(newReserves0 < oldReserves0);
        assert(newReserves1 < oldReserves1);

        // Assert that balances have increased
        assert(finalBalanceA > initialBalanceA);
        assert(finalBalanceB > initialBalanceB);

        vm.stopPrank();
    }

    function testSwap() public {
        // Initial setup
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();
        uint256 balance0Before = tokenA.balanceOf(address(this));
        uint256 balance1Before = tokenB.balanceOf(address(this));

        // Amounts for swap
        uint256 amount0Out = 1 * 10 ** 18; // 1 token A out
        uint256 amount1In = 2 * 10 ** 18; // 2 token B in (more than enough to cover the swap and fee)

        // Perform swap
        tokenB.transfer(address(pair), amount1In);
        uint256 deadline = block.timestamp + 1 hours;
        pair.swap(amount0Out, 0, address(this), deadline);

        // Check results
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
        uint256 balance0After = tokenA.balanceOf(address(this));
        uint256 balance1After = tokenB.balanceOf(address(this));

        // Log values for debugging
        console.log("Reserve0 Before:", reserve0Before);
        console.log("Reserve1 Before:", reserve1Before);
        console.log("Reserve0 After:", reserve0After);
        console.log("Reserve1 After:", reserve1After);
        console.log("Balance0 Before:", balance0Before);
        console.log("Balance1 Before:", balance1Before);
        console.log("Balance0 After:", balance0After);
        console.log("Balance1 After:", balance1After);

        // Assertions
        assertEq(reserve0After, reserve0Before - amount0Out, "Unexpected change in reserve0");
        assertGt(reserve1After, reserve1Before, "Reserve1 should increase");
        assertEq(balance0After, balance0Before + amount0Out, "Unexpected change in balance0");
        assertEq(balance1After, balance1Before - amount1In, "Unexpected change in balance1");

        // Check that K increased (or stayed the same due to rounding)
        uint256 kBefore = uint256(reserve0Before) * uint256(reserve1Before);
        uint256 kAfter = uint256(reserve0After) * uint256(reserve1After);
        assertGe(kAfter, kBefore, "K should not decrease after swap");
    }

    function testSwapFailsAfterDeadline() public {
        uint256 amount0Out = 100 * 10 ** 18;
        uint256 deadline = block.timestamp - 1; // Set deadline in the past

        tokenB.transfer(address(pair), 101 * 10 ** 18);
        vm.expectRevert("UniswapV2: EXPIRED");
        pair.swap(amount0Out, 0, address(this), deadline);
    }

    function testSwapFailsInsufficientLiquidity() public {
        uint256 excessiveAmount = 20000 * 10 ** 18; // More than the available liquidity
        uint256 deadline = block.timestamp + 1 hours;

        vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY");
        pair.swap(excessiveAmount, 0, address(this), deadline);
    }

    function testSwapFailsInvalidK() public {
        uint256 amount0Out = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        // Don't transfer enough tokens to maintain K
        tokenB.transfer(address(pair), 50 * 10 ** 18); // This is not enough to maintain K

        vm.expectRevert("UniswapV2: K");
        pair.swap(amount0Out, 0, address(this), deadline);
    }

    function testFlashLoan() public {
        uint256 flashLoanAmount = 100 * 10 ** 18;
        MockFlashBorrower borrower = new MockFlashBorrower();
        uint256 flashFee = pair.flashFee(address(tokenA), flashLoanAmount);

        tokenA.transfer(address(borrower), flashFee); // Transfer fee to borrower

        uint256 initialBalanceA = tokenA.balanceOf(address(pair));

        pair.flashLoan(borrower, address(tokenA), flashLoanAmount, "");

        uint256 finalBalanceA = tokenA.balanceOf(address(pair));

        // Check that the flash loan was successful and fee was collected
        assertEq(finalBalanceA, initialBalanceA + flashFee);

        // Trigger reserve update
        pair.sync();

        // Check reserves after sync (should include the fee now)
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(reserve0, uint112(initialBalanceA + flashFee));
    }
}

contract MockFlashBorrower is IERC3156FlashBorrower {
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        override
        returns (bytes32)
    {
        ERC20(token).transfer(msg.sender, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
