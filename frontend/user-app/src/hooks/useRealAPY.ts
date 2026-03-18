import { useReadContracts } from "wagmi";
import { useMemo } from "react";
import { getContractAddresses, WAD } from "../config/contracts";
import { BORROW_FEE_ENGINE_ABI, OI_LIMITS_ABI } from "../config/abis";

const MARKET_IDS = [
  "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1",
  "0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a",
  "0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d",
  "0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2",
  "0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7",
  "0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2",
  "0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554",
  "0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc",
  "0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f",
  "0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea",
] as const;

export function useRealAPY(tvl: bigint) {
  const contracts = useMemo(() => getContractAddresses(), []);
  const calls = useMemo(() => {
    const result: any[] = [];
    for (const marketId of MARKET_IDS) {
      result.push({ address: contracts.borrowFeeEngine, abi: BORROW_FEE_ENGINE_ABI, functionName: "getAnnualizedRate", args: [marketId, true] });
      result.push({ address: contracts.borrowFeeEngine, abi: BORROW_FEE_ENGINE_ABI, functionName: "getAnnualizedRate", args: [marketId, false] });
      result.push({ address: contracts.oiLimits, abi: OI_LIMITS_ABI, functionName: "getSideOI", args: [marketId, true] });
      result.push({ address: contracts.oiLimits, abi: OI_LIMITS_ABI, functionName: "getSideOI", args: [marketId, false] });
    }
    return result;
  }, [contracts]);
  const { data, isLoading } = useReadContracts({ contracts: calls, query: { enabled: tvl > 0n, retry: 2, refetchInterval: 30000 } });
  return useMemo(() => {
    if (data = sys.stdin.read().strip() || isLoading || tvl === 0n) return { apyPercent: 0, isLoading };
    let totalWeightedRevenue = 0n;
    for (let i = 0; i < MARKET_IDS.length; i++) {
      const b = i * 4;
      try {
        const lr = BigInt((data[b]?.result as any) ?? 0n);
        const sr = BigInt((data[b+1]?.result as any) ?? 0n);
        const lo = BigInt((data[b+2]?.result as any) ?? 0n);
        const so = BigInt((data[b+3]?.result as any) ?? 0n);
        totalWeightedRevenue += (lr * lo / WAD) + (sr * so / WAD);
      } catch { continue; }
    }
    const lpRevenue = totalWeightedRevenue * 50n / 100n;
    const apyBps = tvl > 0n ? Number(lpRevenue * 10000n / tvl) : 0;
    const apyPercent = apyBps / 100;
    return { apyPercent: isFinite(apyPercent) && apyPercent >= 0 ? apyPercent : 0, isLoading: false };
  }, [data, isLoading, tvl]);
}
