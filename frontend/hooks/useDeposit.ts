"use client";

import { useState } from "react";
import {
  decodeEventLog,
  type TransactionReceipt,
  type WalletClient,
  WaitForTransactionReceiptTimeoutError,
} from "viem";
import type { Product } from "@/hooks/useProducts";
import { ADDRESSES, erc20Abi, riskOracleAbi, routerAbi, TOKEN_META } from "@/lib/contracts";
import { publicClient, paseoAssetHub } from "@/lib/viem";

export type DepositResult =
  | { type: "local"; yieldTokens: string; txHash: `0x${string}` }
  | { type: "xcm"; receiptId: string; txHash: `0x${string}` };

export type DepositState =
  | { status: "idle" }
  | { status: "approving"; txHash?: `0x${string}`; phase: "signature" | "network" }
  | { status: "depositing"; txHash?: `0x${string}`; phase: "signature" | "network" }
  | { status: "confirmed"; result: DepositResult }
  | { status: "error"; message: string };

type ParsedDepositResult =
  | { type: "local"; yieldTokens: string }
  | { type: "xcm"; receiptId: string };

const GAS_HARD_CAP = BigInt(3_000_000);
const GAS_FALLBACK_APPROVE = BigInt(120_000);
const GAS_FALLBACK_DEPOSIT = BigInt(900_000);

function withGasBuffer(estimated: bigint): bigint {
  return (estimated * BigInt(120)) / BigInt(100);
}

function resolveSafeGas(estimated: bigint, fallback: bigint): bigint {
  const buffered = withGasBuffer(estimated);
  if (buffered > GAS_HARD_CAP) {
    return fallback;
  }
  return buffered;
}

function parseContractError(err: unknown): string {
  const msg = err instanceof Error ? err.message : "";
  const lower = msg.toLowerCase();

  // Custom error selector for RiskScoreTooLow(uint256,uint256)
  const riskSelector = "0x3ae9ae60";
  const match = msg.match(/0x3ae9ae60([0-9a-fA-F]{64})([0-9a-fA-F]{64})/);
  if (match) {
    const current = BigInt(`0x${match[1]}`);
    const minimum = BigInt(`0x${match[2]}`);
    return `Risk score too low. Current: ${current.toString()}, minimum: ${minimum.toString()}. Lower your slider or wait for score updates.`;
  }

  if (msg.includes(riskSelector) || msg.includes("RiskScoreTooLow")) {
    return "Risk score too low. Reduce your minimum threshold or wait for the product score to improve.";
  }

  // Custom error selector for InsufficientBalance(address,uint256,uint256)
  const insufficientBalanceSelector = "0xdb42144d";
  const insufficientMatch = msg.match(/0xdb42144d[0-9a-fA-F]{64}([0-9a-fA-F]{64})([0-9a-fA-F]{64})/);
  if (insufficientMatch) {
    const required = BigInt(`0x${insufficientMatch[1]}`);
    const available = BigInt(`0x${insufficientMatch[2]}`);
    return `Insufficient token balance for this amount. Required: ${required.toString()} raw units, available: ${available.toString()} raw units.`;
  }
  if (msg.includes(insufficientBalanceSelector) || lower.includes("insufficientbalance")) {
    return "Insufficient token balance for this amount.";
  }

  if (lower.includes("insufficientallowance") || lower.includes("allowance")) {
    return "Insufficient token allowance. The approval may have failed.";
  }
  if (lower.includes("user rejected") || lower.includes("user denied")) {
    return "Transaction rejected in wallet.";
  }
  if (lower.includes("chain") || lower.includes("network")) {
    return "Please switch wallet network to Paseo Asset Hub and try again.";
  }
  if (lower.includes("execution reverted")) {
    return "Call reverted before broadcast. No transaction was mined. Check amount, allowance, and risk threshold.";
  }

  return msg || "Transaction failed. Check your wallet and try again.";
}

function parseDepositResult(receipt: TransactionReceipt, isXCM: boolean): ParsedDepositResult | null {
  for (const log of receipt.logs) {
    try {
      const decoded = decodeEventLog({
        abi: routerAbi,
        data: log.data,
        topics: log.topics,
      });

      if (!isXCM && decoded.eventName === "Deposited") {
        const tokensOut = decoded.args.tokensOut as bigint;
        return { type: "local", yieldTokens: tokensOut.toString() };
      }

      if (isXCM && decoded.eventName === "XCMDispatched") {
        const receiptId = decoded.args.receiptId as bigint;
        return { type: "xcm", receiptId: receiptId.toString() };
      }
    } catch {
      continue;
    }
  }

  return null;
}

export function useDeposit(product: Product) {
  const [state, setState] = useState<DepositState>({ status: "idle" });

  async function deposit(
    amountRaw: bigint,
    minRiskScore: bigint,
    walletClient: WalletClient | null,
    address: `0x${string}` | null,
  ) {
    if (!walletClient || !address) {
      setState({ status: "error", message: "Connect wallet to continue." });
      return;
    }

    if (amountRaw === BigInt(0)) {
      setState({ status: "error", message: "Enter an amount greater than 0." });
      return;
    }

    try {
      const chainId = await walletClient.getChainId();
      if (chainId !== paseoAssetHub.id) {
        try {
          await walletClient.switchChain({ id: paseoAssetHub.id });
        } catch {
          setState({
            status: "error",
            message: "Wrong network. Switch to Paseo Asset Hub in wallet.",
          });
          return;
        }
      }

      const tokenAddress = product.isXCM ? TOKEN_META.mockDOT.address : TOKEN_META.mUSDC.address;

      // Preflight risk check prevents paying gas for a known on-chain revert.
      const currentRiskScore = (await publicClient.readContract({
        address: ADDRESSES.riskOracle,
        abi: riskOracleAbi,
        functionName: "getScore",
        args: [product.productId],
      })) as bigint;

      if (currentRiskScore < minRiskScore) {
        setState({
          status: "error",
          message: `Risk score too low. Current: ${currentRiskScore.toString()}, minimum: ${minRiskScore.toString()}. Lower your minimum risk slider to continue.`,
        });
        return;
      }

      const allowance = (await publicClient.readContract({
        address: tokenAddress,
        abi: erc20Abi,
        functionName: "allowance",
        args: [address, ADDRESSES.conduitRouter],
      })) as bigint;

      if (allowance < amountRaw) {
        setState({ status: "approving", phase: "signature" });

        let approveGas = GAS_FALLBACK_APPROVE;
        try {
          const estimatedApproveGas = await publicClient.estimateContractGas({
            account: address,
            address: tokenAddress,
            abi: erc20Abi,
            functionName: "approve",
            args: [ADDRESSES.conduitRouter, amountRaw],
          });
          approveGas = resolveSafeGas(estimatedApproveGas, GAS_FALLBACK_APPROVE);
        } catch {
          approveGas = GAS_FALLBACK_APPROVE;
        }

        const approveHash = await walletClient.writeContract({
          account: address,
          chain: paseoAssetHub,
          address: tokenAddress,
          abi: erc20Abi,
          functionName: "approve",
          args: [ADDRESSES.conduitRouter, amountRaw],
          gas: approveGas,
        });

        setState({ status: "approving", phase: "network", txHash: approveHash });

        await publicClient.waitForTransactionReceipt({ hash: approveHash });
      }

      setState({ status: "depositing", phase: "signature" });

      let depositGas = GAS_FALLBACK_DEPOSIT;
      try {
        const estimatedDepositGas = await publicClient.estimateContractGas({
          account: address,
          address: ADDRESSES.conduitRouter,
          abi: routerAbi,
          functionName: "deposit",
          args: [product.productId, amountRaw, minRiskScore],
        });
        depositGas = resolveSafeGas(estimatedDepositGas, GAS_FALLBACK_DEPOSIT);
      } catch {
        depositGas = GAS_FALLBACK_DEPOSIT;
      }

      const depositHash = await walletClient.writeContract({
        account: address,
        chain: paseoAssetHub,
        address: ADDRESSES.conduitRouter,
        abi: routerAbi,
        functionName: "deposit",
        args: [product.productId, amountRaw, minRiskScore],
        gas: depositGas,
      });

      setState({ status: "depositing", phase: "network", txHash: depositHash });

      let receipt: TransactionReceipt;
      try {
        receipt = await publicClient.waitForTransactionReceipt({
          hash: depositHash,
          timeout: 120_000,
          pollingInterval: 2_000,
        });
      } catch (err) {
        if (err instanceof WaitForTransactionReceiptTimeoutError) {
          setState({
            status: "error",
            message: `Transaction submitted but not mined yet. Check Blockscout with tx hash: ${depositHash}`,
          });
          return;
        }
        throw err;
      }

      if (receipt.status !== "success") {
        setState({
          status: "error",
          message: "Deposit transaction reverted on-chain. Check Blockscout for details.",
        });
        return;
      }

      const parsed = parseDepositResult(receipt, product.isXCM);
      if (!parsed) {
        setState({
          status: "error",
          message: "Transaction included, but no deposit success event was found. Please verify in Blockscout.",
        });
        return;
      }

      setState({ status: "confirmed", result: { ...parsed, txHash: depositHash } });
    } catch (err) {
      setState({ status: "error", message: parseContractError(err) });
    }
  }

  return {
    state,
    deposit,
    reset: () => setState({ status: "idle" }),
  };
}
