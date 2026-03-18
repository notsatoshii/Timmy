import { createWalletClient, createPublicClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { baseSepolia } from 'viem/chains';
import { TEST_WALLET_KEY } from '../connectors/demo';
import { useDemo } from '../contexts/DemoContext';

const account = privateKeyToAccount(`0x${TEST_WALLET_KEY}`);

const walletClient = createWalletClient({
  account,
  chain: baseSepolia,
  transport: http('https://sepolia.base.org'),
});

const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http('https://sepolia.base.org'),
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

    const { request } = await publicClient.simulateContract({
      account,
      address: params.address,
      abi: params.abi,
      functionName: params.functionName,
      args: params.args,
    });

    const hash = await walletClient.writeContract(request);

    // Wait for receipt
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    return { hash, receipt };
  };

  return {
    isDemoMode,
    sendTransaction,
    account,
  };
};
