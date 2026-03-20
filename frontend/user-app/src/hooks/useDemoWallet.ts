import { createWalletClient, createPublicClient, http, encodeFunctionData } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { baseSepolia } from 'viem/chains';
import { TEST_WALLET_KEY } from '../connectors/demo';
import { useDemo } from '../contexts/DemoContext';

const account = privateKeyToAccount(`0x${TEST_WALLET_KEY}`);

const walletClient = createWalletClient({
  account,
  chain: baseSepolia,
  transport: http('https://base-sepolia-rpc.publicnode.com'),
});

const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http('https://base-sepolia-rpc.publicnode.com'),
});

export const useDemoWallet = () => {
  const { isDemoMode } = useDemo();

  const sendTransaction = async (params: {
    address: `0x${string}`;
    abi: any;
    functionName: string;
    args: any[];
  }) => {
    if (!isDemoMode) throw new Error('Not in demo mode');

    // Skip simulation — send directly with manual gas
    // Simulation fails on contracts with internal reverts that are caught
    const nonce = await publicClient.getTransactionCount({ address: account.address, blockTag: 'pending' });
    const hash = await walletClient.writeContract({
      address: params.address,
      abi: params.abi,
      functionName: params.functionName,
      args: params.args,
      account,
      chain: baseSepolia,
      gas: 800000n,
      nonce,
    });

    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    return { hash, receipt };
  };

  return {
    isDemoMode,
    sendTransaction,
    account,
  };
};
