// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CredibleTest} from "credible-std/CredibleTest.sol";
import {Test} from "forge-std/Test.sol";
import {BatchSwapDeltaAssertion} from "../src/BatchSwapDeltaAssertion.a.sol";
import "@balancer-labs/v2-interfaces/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/vault/IAsset.sol";
import "@balancer-labs/v2-interfaces/solidity-utils/openzeppelin/IERC20.sol";

/**
 * @title MockBatchSwapTest
 * @notice Unit tests for BatchSwapDeltaAssertion using a mock Vault
 */
contract MockBatchSwapTest is CredibleTest, Test {
    MockVault public vault;
    MockToken public tokenA;
    MockToken public tokenB;
    MockToken public tokenC;
    MockToken public tokenD;

    function setUp() public {
        // Deploy mock contracts
        vault = new MockVault();
        tokenA = new MockToken("Token A", "TKA");
        tokenB = new MockToken("Token B", "TKB");
        tokenC = new MockToken("Token C", "TKC");
        tokenD = new MockToken("Token D", "TKD");

        // Give vault initial balances
        tokenA.mint(address(vault), 1000 ether);
        tokenB.mint(address(vault), 1000 ether);
        tokenC.mint(address(vault), 1000 ether);
        tokenD.mint(address(vault), 1000 ether);
    }

    /// @notice Test valid swap: one asset in, one asset out
    function testValidSwap_OnePositiveOneNegative() public {
        // Setup: Token A increases (+100), Token B decreases (-100)
        vault.setBalanceChange(address(tokenA), 100 ether);
        vault.setBalanceChange(address(tokenB), -100 ether);

        // Register assertion
        cl.assertion({
            adopter: address(vault),
            createData: type(BatchSwapDeltaAssertion).creationCode,
            fnSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector
        });

        // Execute batchSwap - should pass
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokenA));
        assets[1] = IAsset(address(tokenB));

        vault.executeBatchSwap(assets);
    }

    /// @notice Test valid swap: one asset in, one unchanged
    function testValidSwap_OnePositiveOneZero() public {
        // Setup: Token A increases (+100), Token B stays same (0)
        vault.setBalanceChange(address(tokenA), 100 ether);
        vault.setBalanceChange(address(tokenB), 0);

        cl.assertion({
            adopter: address(vault),
            createData: type(BatchSwapDeltaAssertion).creationCode,
            fnSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector
        });

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokenA));
        assets[1] = IAsset(address(tokenB));

        vault.executeBatchSwap(assets);
    }

    /// @notice Test exploit: both assets decrease (value drainage)
    function testExploit_BothNegativeDeltas() public {
        // Setup: Both tokens decrease (vault sends both, receives nothing)
        vault.setBalanceChange(address(tokenA), -100 ether);
        vault.setBalanceChange(address(tokenB), -50 ether);

        cl.assertion({
            adopter: address(vault),
            createData: type(BatchSwapDeltaAssertion).creationCode,
            fnSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector
        });

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokenA));
        assets[1] = IAsset(address(tokenB));

        vm.expectRevert("BatchSwap: All deltas negative - value drainage detected");
        vault.executeBatchSwap(assets);
    }

    /// @notice Test exploit: all three assets decrease
    function testExploit_AllNegativeDeltas_ThreeAssets() public {
        // Setup: All three tokens decrease
        vault.setBalanceChange(address(tokenA), -100 ether);
        vault.setBalanceChange(address(tokenB), -50 ether);
        vault.setBalanceChange(address(tokenC), -25 ether);

        cl.assertion({
            adopter: address(vault),
            createData: type(BatchSwapDeltaAssertion).creationCode,
            fnSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector
        });

        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(tokenA));
        assets[1] = IAsset(address(tokenB));
        assets[2] = IAsset(address(tokenC));

        vm.expectRevert("BatchSwap: All deltas negative - value drainage detected");
        vault.executeBatchSwap(assets);
    }

    /// @notice Test valid complex swap: two in, one out
    function testValidSwap_TwoPositiveOneNegative() public {
        // Setup: Two tokens increase, one decreases
        vault.setBalanceChange(address(tokenA), 100 ether);
        vault.setBalanceChange(address(tokenB), 50 ether);
        vault.setBalanceChange(address(tokenC), -150 ether);

        cl.assertion({
            adopter: address(vault),
            createData: type(BatchSwapDeltaAssertion).creationCode,
            fnSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector
        });

        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(tokenA));
        assets[1] = IAsset(address(tokenB));
        assets[2] = IAsset(address(tokenC));

        vault.executeBatchSwap(assets);
    }

    /// @notice Test with actual mainnet exploit deltas from tx 0x3e173ab0ba9183efa8a42caa783bdb5ec75daffcc8505cc1302009d11daf1ccf
    function testExploit_MainnetExploitDeltas_FourAssets() public {
        // Asset 0: -0.193591169852954638 tokens
        vault.setBalanceChange(address(tokenA), -193591169852954638);
        // Asset 1: -31.662310067848063306 tokens
        vault.setBalanceChange(address(tokenB), -31662310067848063306);
        // Asset 2: -28.118450452589360458 tokens
        vault.setBalanceChange(address(tokenC), -28118450452589360458);
        // Asset 3: -73.999482583474200583 tokens
        vault.setBalanceChange(address(tokenD), -73999482583474200583);

        cl.assertion({
            adopter: address(vault),
            createData: type(BatchSwapDeltaAssertion).creationCode,
            fnSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector
        });

        IAsset[] memory assets = new IAsset[](4);
        assets[0] = IAsset(address(tokenA));
        assets[1] = IAsset(address(tokenB));
        assets[2] = IAsset(address(tokenC));
        assets[3] = IAsset(address(tokenD));

        vm.expectRevert("BatchSwap: All deltas negative - value drainage detected");
        vault.executeBatchSwap(assets);
    }

    /// @notice Test with smaller exploit deltas from earlier in the trace
    function testExploit_SmallerNegativeDeltas() public {
        // Setup: Smaller negative deltas (still an exploit)
        vault.setBalanceChange(address(tokenA), -1 ether);
        vault.setBalanceChange(address(tokenB), -0.5 ether);

        cl.assertion({
            adopter: address(vault),
            createData: type(BatchSwapDeltaAssertion).creationCode,
            fnSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector
        });

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokenA));
        assets[1] = IAsset(address(tokenB));

        vm.expectRevert("BatchSwap: All deltas negative - value drainage detected");
        vault.executeBatchSwap(assets);
    }

    /// @notice Test edge case: very small negative amounts (dust attack)
    function testExploit_DustAmountsAllNegative() public {
        // Setup: Very small negative amounts (still exploitable)
        vault.setBalanceChange(address(tokenA), -1000); // 1000 wei
        vault.setBalanceChange(address(tokenB), -500); // 500 wei

        cl.assertion({
            adopter: address(vault),
            createData: type(BatchSwapDeltaAssertion).creationCode,
            fnSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector
        });

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokenA));
        assets[1] = IAsset(address(tokenB));

        vm.expectRevert("BatchSwap: All deltas negative - value drainage detected");
        vault.executeBatchSwap(assets);
    }

    /// @notice Test valid swap with mixed large and small values
    function testValidSwap_MixedMagnitudes() public {
        // Setup: Large positive, small negative (valid swap with unbalanced amounts)
        vault.setBalanceChange(address(tokenA), 100 ether); // Large deposit
        vault.setBalanceChange(address(tokenB), -0.001 ether); // Small withdrawal

        cl.assertion({
            adopter: address(vault),
            createData: type(BatchSwapDeltaAssertion).creationCode,
            fnSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector
        });

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokenA));
        assets[1] = IAsset(address(tokenB));

        vault.executeBatchSwap(assets);
    }
}

/**
 * @title MockVault
 * @notice Simplified Vault implementation for testing
 */
contract MockVault {
    // Track balance changes we want to simulate
    mapping(address => int256) public balanceChanges;
    mapping(address => uint256) public initialBalances;

    function setBalanceChange(address token, int256 change) external {
        balanceChanges[token] = change;
        initialBalances[token] = IERC20(token).balanceOf(address(this));
    }

    function batchSwap(
        IVault.SwapKind,
        IVault.BatchSwapStep[] memory,
        IAsset[] memory assets,
        IVault.FundManagement memory,
        int256[] memory,
        uint256
    ) external returns (int256[] memory) {
        // Apply balance changes
        for (uint256 i = 0; i < assets.length; i++) {
            address token = address(assets[i]);
            if (token == address(0)) continue;

            int256 change = balanceChanges[token];
            if (change > 0) {
                // Vault receives tokens
                MockToken(token).mint(address(this), uint256(change));
            } else if (change < 0) {
                // Vault sends tokens
                MockToken(token).burn(address(this), uint256(-change));
            }
        }

        // Return deltas (negative of balance changes from Vault's perspective)
        int256[] memory deltas = new int256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            deltas[i] = -balanceChanges[address(assets[i])];
        }
        return deltas;
    }

    function executeBatchSwap(IAsset[] memory assets) external {
        IVault.SwapKind kind = IVault.SwapKind.GIVEN_IN;
        IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](0);
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        int256[] memory limits = new int256[](assets.length);
        uint256 deadline = block.timestamp + 1000;

        this.batchSwap(kind, swaps, assets, funds, limits, deadline);
    }
}

/**
 * @title MockToken
 * @notice Simple ERC20 for testing
 */
contract MockToken is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
