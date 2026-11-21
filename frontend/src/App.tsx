
import { useEffect, useState } from 'react'
import {
  useAccount,
  useConnect,
  useDisconnect,
  useReadContract,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from 'wagmi'
import {
  formatEther,
  formatUnits,
  parseEther,
  zeroAddress,
} from 'viem'
import {
  ArrowDownToLine,
  ArrowUpRight,
  CheckCircle2,
  CircleDollarSign,
  Clock3,
  ExternalLink,
  HeartHandshake,
  LoaderCircle,
  LockKeyhole,
  ShieldCheck,
  Wallet,
  XCircle,
} from 'lucide-react'

import {
  FUNDME_ABI,
  FUNDME_ADDRESS,
  SEPOLIA_CHAIN_ID,
} from './contracts'

const explorer = `https://sepolia.etherscan.io/address/${FUNDME_ADDRESS}`

const stateLabels = ['ACTIVE', 'SUCCESS', 'FAILED']

const formatUSD = (value: bigint) =>
  Number(formatUnits(value, 18)).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })

function App() {
  const { address, isConnected, chainId } = useAccount()
  const { connect, connectors, isPending: connecting } = useConnect()
  const { disconnect } = useDisconnect()
  const { switchChain } = useSwitchChain()

  const [amount, setAmount] = useState('')
  const [withdrawAmount, setWithdrawAmount] = useState('')
  const [notice, setNotice] = useState('')

  const correctNetwork = chainId === SEPOLIA_CHAIN_ID

  const contract = {
    address: FUNDME_ADDRESS,
    abi: FUNDME_ABI,
    chainId: SEPOLIA_CHAIN_ID,
  } as const

  // ─────────────────────────────────────
  // ON-CHAIN DATA
  // ─────────────────────────────────────

  const goalQuery = useReadContract({
    ...contract,
    functionName: 'i_goalUsd',
    query: { refetchInterval: 15000 },
  })

  const minimumQuery = useReadContract({
    ...contract,
    functionName: 'i_minimumUsd',
  })

  const raisedEthQuery = useReadContract({
    ...contract,
    functionName: 'getTotalAmountFunded',
    query: { refetchInterval: 15000 },
  })

  const raisedUsdQuery = useReadContract({
    ...contract,
    functionName: 'getTotalAmountFundedUsd',
    query: { refetchInterval: 15000 },
  })

  const stateQuery = useReadContract({
    ...contract,
    functionName: 'getState',
    query: { refetchInterval: 15000 },
  })

  const deadlineQuery = useReadContract({
    ...contract,
    functionName: 'getDeadline',
    query: { refetchInterval: 15000 },
  })

  const ownerQuery = useReadContract({
    ...contract,
    functionName: 'owner',
  })

  const contributionQuery = useReadContract({
    ...contract,
    functionName: 'getAddressToAmountFunded',
    args: [address ?? zeroAddress],
    query: {
      enabled: isConnected && correctNetwork,
      refetchInterval: 15000,
    },
  })

  const feesQuery = useReadContract({
    ...contract,
    functionName: 'getPlatformFeesCollected',
    query: { refetchInterval: 15000 },
  })

  const withdrawnQuery = useReadContract({
    ...contract,
    functionName: 'getTotalWithdrawnByOwner',
    query: { refetchInterval: 15000 },
  })

  // ─────────────────────────────────────
  // TRANSACTION MANAGEMENT
  // ─────────────────────────────────────

  const {
    writeContract,
    data: txHash,
    isPending,
    error: writeError,
  } = useWriteContract()

  const {
    isLoading: confirming,
    isSuccess: confirmed,
    error: receiptError,
  } = useWaitForTransactionReceipt({
    hash: txHash,
  })

  // ─────────────────────────────────────
  // DERIVED CONTRACT DATA
  // ─────────────────────────────────────

  const goal = BigInt(goalQuery.data?.toString() ?? '0')
  const minimum = BigInt(minimumQuery.data?.toString() ?? '0')
  const raisedEth = BigInt(raisedEthQuery.data?.toString() ?? '0')
  const raisedUsd = BigInt(raisedUsdQuery.data?.toString() ?? '0')
  const contribution = BigInt(contributionQuery.data?.toString() ?? '0')
  const fees = BigInt(feesQuery.data?.toString() ?? '0')
  const withdrawn = BigInt(withdrawnQuery.data?.toString() ?? '0')

  const deadline = Number(deadlineQuery.data ?? 0)
  const campaignState = Number(stateQuery.data ?? 0)

  const owner = (ownerQuery.data as string | undefined)?.toLowerCase()

  const isOwner = Boolean(
    address && owner && address.toLowerCase() === owner,
  )

  const stateLabel = stateLabels[campaignState] ?? 'LOADING'

  const progress =
    goal > 0n
      ? Math.min(Number((raisedUsd * 10000n) / goal) / 100, 100)
      : 0

  // ─────────────────────────────────────
  // CAMPAIGN COUNTDOWN
  // ─────────────────────────────────────

  const [now, setNow] = useState(Date.now())

  useEffect(() => {
    const interval = setInterval(() => {
      setNow(Date.now())
    }, 1000)

    return () => clearInterval(interval)
  }, [])

  const secondsLeft = Math.max(
    deadline - Math.floor(now / 1000),
    0,
  )

  const days = Math.floor(secondsLeft / 86400)
  const hours = Math.floor((secondsLeft % 86400) / 3600)
  const minutes = Math.floor((secondsLeft % 3600) / 60)

  // ─────────────────────────────────────
  // REFRESH ON-CHAIN DATA
  // ─────────────────────────────────────

  const refresh = () => {
    void goalQuery.refetch()
    void minimumQuery.refetch()
    void raisedEthQuery.refetch()
    void raisedUsdQuery.refetch()
    void stateQuery.refetch()
    void deadlineQuery.refetch()
    void contributionQuery.refetch()
    void feesQuery.refetch()
    void withdrawnQuery.refetch()
  }

  useEffect(() => {
    if (confirmed) {
      setNotice('Transaction confirmed successfully.')
      setAmount('')
      setWithdrawAmount('')
      refresh()
    }
  }, [confirmed])

  // ─────────────────────────────────────
  // CONTRACT WRITE FUNCTIONS
  // ─────────────────────────────────────

  const handleFund = () => {
    setNotice('')

    try {
      if (!amount || !Number.isFinite(Number(amount)) || Number(amount) <= 0) {
        setNotice('Enter a valid ETH amount.')
        return
      }

      writeContract({
        ...contract,
        functionName: 'fund',
        value: parseEther(amount),
      })
    } catch {
      setNotice('Invalid ETH amount.')
    }
  }

  const handleRefund = () => {
    setNotice('')

    writeContract({
      ...contract,
      functionName: 'refund',
    })
  }

  const handleFinalize = () => {
    setNotice('')

    writeContract({
      ...contract,
      functionName: 'finalizeCampaign',
    })
  }

  const handleWithdraw = () => {
    setNotice('')

    try {
      const value = withdrawAmount.trim()
        ? parseEther(withdrawAmount)
        : 0n

      writeContract({
        ...contract,
        functionName: 'ownerWithdraw',
        args: [value],
      })
    } catch {
      setNotice('Enter a valid ETH withdrawal amount.')
    }
  }

  const busy = isPending || confirming

  const loading = [
    goalQuery,
    minimumQuery,
    raisedEthQuery,
    raisedUsdQuery,
    stateQuery,
    deadlineQuery,
    ownerQuery,
  ].some((query) => query.isLoading)

  const error = writeError?.message ?? receiptError?.message

  // ─────────────────────────────────────
  // UI
  // ─────────────────────────────────────

  return (
    <main className="app-shell px-5 py-4 md:px-8">
      <div className="app-container mx-auto max-w-7xl">

        {/* HEADER */}

        <header className="app-header flex flex-wrap items-center justify-between gap-3">

          <a href="/" className="flex items-center gap-3">
            <div className="rounded-xl bg-[#a855f7] p-2.5">
              <HeartHandshake size={25} className="text-white" />
            </div>

            <div>
              <h1 className="text-xl font-bold tracking-tight text-white">
                FundMe
              </h1>

              <p className="text-xs text-slate-400">
                Secure Crowdfunding Protocol
              </p>
            </div>
          </a>

          <div className="flex items-center gap-2">

            <span className="rounded-full border border-[#a855f7]/30 bg-[#a855f7]/10 px-3 py-2 text-xs font-medium text-[#c084fc]">
              Sepolia Testnet
            </span>

            {!isConnected ? (
              <button
                onClick={() => connect({ connector: connectors[0] })}
                disabled={connecting || connectors.length === 0}
                className="flex items-center gap-2 rounded-xl bg-[#a855f7] px-4 py-3 text-sm font-semibold text-white transition hover:bg-[#9333ea]"
              >
                <Wallet size={17} />
                {connecting ? 'Connecting...' : 'Connect Wallet'}
              </button>
            ) : (
              <div className="flex items-center gap-2">
                <span className="rounded-xl border border-slate-700 px-3 py-3 text-xs text-slate-300">
                  {address?.slice(0, 6)}...{address?.slice(-4)}
                </span>

                <button
                  onClick={() => disconnect()}
                  className="rounded-xl border border-slate-700 px-3 py-3 text-xs text-slate-300 transition hover:bg-slate-800"
                >
                  Disconnect
                </button>
              </div>
            )}
          </div>
        </header>

        {/* CAMPAIGN OVERVIEW */}

        <section className="app-hero grid gap-5 lg:grid-cols-[1.1fr_0.9fr] lg:items-center">

          {/* HERO CONTENT */}

          <div className="flex flex-col justify-center">

            <span className="inline-flex w-fit items-center gap-2 rounded-full border border-[#a855f7]/20 bg-[#a855f7]/10 px-3 py-2 text-xs font-medium text-[#c084fc]">
              <span className="h-2 w-2 rounded-full bg-[#a855f7]" />
              On-chain crowdfunding
            </span>

            <h2 className="mt-5 max-w-2xl text-4xl font-bold leading-tight tracking-tight text-white md:text-6xl">
              Fund ideas.
              <span className="text-[#a855f7]"> Build the future.</span>
            </h2>

            <p className="mt-4 max-w-xl text-sm leading-6 text-slate-400 md:text-base">
              Support this campaign directly on Ethereum. Every contribution
              is recorded transparently on-chain, powered by smart contracts
              and Chainlink price feeds.
            </p>

            <div className="mt-6 flex flex-wrap items-center gap-3">

              <a
                href={explorer}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-2 rounded-xl border border-slate-700 px-4 py-3 text-sm font-medium text-white transition hover:border-[#a855f7] hover:bg-[#a855f7]/10"
              >
                View Contract
                <ExternalLink size={15} />
              </a>

              <span className="inline-flex items-center gap-2 text-xs text-slate-500">
                <LockKeyhole size={15} />
                Non-custodial · Ethereum Sepolia
              </span>
            </div>

          </div>

          {/* CAMPAIGN STATISTICS */}

          <div className="rounded-3xl border border-slate-700/70 bg-gradient-to-br from-[#182333] to-[#111722] p-5 shadow-xl shadow-black/10 md:p-6">

            <div className="flex items-center justify-between">
              <p className="text-sm font-medium text-slate-400">
                Campaign progress
              </p>

              <span className={`rounded-full px-3 py-1.5 text-xs font-semibold ${
                campaignState === 1
                  ? 'bg-emerald-400/10 text-emerald-400'
                  : campaignState === 2
                    ? 'bg-red-400/10 text-red-400'
                    : 'bg-[#a855f7]/10 text-[#c084fc]'
              }`}>
                {stateLabel}
              </span>
            </div>

            <div className="mt-5">
              <p className="text-4xl font-bold tracking-tight text-white">
                ${formatUSD(raisedUsd)}
              </p>

              <p className="mt-1 text-sm text-slate-400">
                raised of ${formatUSD(goal)} goal
              </p>
            </div>

            {/* PROGRESS BAR */}

            <div className="mt-5 h-2.5 overflow-hidden rounded-full bg-slate-700/70">
              <div
                className="h-full rounded-full bg-gradient-to-r from-[#a855f7] to-[#2ebac6] transition-all duration-500"
                style={{ width: `${progress}%` }}
              />
            </div>

            <div className="mt-3 flex justify-between text-xs text-slate-500">
              <span>{progress.toFixed(2)}% funded</span>
              <span>{formatEther(raisedEth)} ETH raised</span>
            </div>

            {/* CAMPAIGN METRICS */}

            <div className="mt-5 grid grid-cols-2 gap-3">

              <div className="rounded-2xl border border-slate-700/50 bg-[#0d1420]/70 p-4">
                <CircleDollarSign size={20} className="text-[#a855f7]" />

                <p className="mt-2 text-lg font-semibold text-white">
                  ${formatUSD(minimum)}
                </p>

                <p className="mt-1 text-xs text-slate-500">
                  Minimum contribution
                </p>
              </div>

              <div className="rounded-2xl border border-slate-700/50 bg-[#0d1420]/70 p-4">
                <Clock3 size={20} className="text-[#2ebac6]" />

                <p className="mt-2 text-lg font-semibold text-white">
                  {deadline === 0
                    ? '--'
                    : secondsLeft === 0
                      ? 'Ended'
                      : `${days}d ${hours}h ${minutes}m`}
                </p>

                <p className="mt-1 text-xs text-slate-500">
                  Time remaining
                </p>
              </div>

            </div>
          </div>
        </section>

        {/* CONTRIBUTION AND MANAGEMENT */}

        <section className="app-actions grid gap-4 lg:grid-cols-2">

          {/* CONTRIBUTION PANEL */}

          <div className="rounded-3xl border border-slate-700/70 bg-[#111722] p-5 md:p-6">

            <div className="flex items-center gap-3">
              <div className="rounded-xl bg-[#a855f7]/10 p-3 text-[#c084fc]">
                <HeartHandshake size={22} />
              </div>

              <div>
                <h3 className="font-semibold text-white">
                  Support the campaign
                </h3>

                <p className="text-xs text-slate-500">
                  Contribute ETH directly to the contract
                </p>
              </div>
            </div>

            <label className="mt-5 block text-sm font-medium text-slate-400">
              Contribution amount
            </label>

            <div className="mt-2 flex items-center rounded-xl border border-slate-700 bg-[#0d131d] px-4 transition focus-within:border-[#a855f7]">
              <input
                value={amount}
                onChange={(event) => setAmount(event.target.value)}
                type="number"
                min="0"
                step="any"
                placeholder="0.01"
                className="w-full bg-transparent py-3.5 text-lg text-white outline-none"
              />

              <span className="text-sm font-semibold text-slate-400">
                ETH
              </span>
            </div>

            <button
              onClick={handleFund}
              disabled={
                !isConnected ||
                !correctNetwork ||
                busy ||
                campaignState !== 0
              }
              className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-[#a855f7] py-3.5 font-semibold text-white transition hover:bg-[#9333ea]"
            >
              {busy
                ? <LoaderCircle className="animate-spin" size={18} />
                : <ArrowUpRight size={18} />}

              {busy ? 'Processing...' : 'Contribute ETH'}
            </button>

            <div className="mt-4 flex flex-wrap items-center justify-between gap-2 text-xs">
              <span className="text-slate-500">
                Your contribution
              </span>

              <span className="font-semibold text-white">
                {isConnected && correctNetwork
                  ? `${formatEther(contribution)} ETH`
                  : 'Connect wallet'}
              </span>
            </div>

            {isConnected && correctNetwork && (
              <p className="mt-2 text-xs text-slate-500">
                Minimum requirement: ${formatUSD(minimum)}
              </p>
            )}
          </div>

          {/* CAMPAIGN MANAGEMENT */}

          <div className="rounded-3xl border border-slate-700/70 bg-[#111722] p-5 md:p-6">

            <div className="flex items-center gap-3">
              <div className="rounded-xl bg-[#2ebac6]/10 p-3 text-[#2ebac6]">
                {isOwner
                  ? <ShieldCheck size={22} />
                  : <Wallet size={22} />}
              </div>

              <div>
                <h3 className="font-semibold text-white">
                  Campaign management
                </h3>

                <p className="text-xs text-slate-500">
                  Contract-controlled actions
                </p>
              </div>
            </div>

            {/* OWNER: ACTIVE CAMPAIGN */}

            {isOwner && campaignState === 0 && (
              <div className="mt-5">
                <div className="rounded-xl border border-[#a855f7]/20 bg-[#a855f7]/5 p-4">
                  <p className="text-sm font-semibold text-[#c084fc]">
                    Campaign owner
                  </p>

                  <p className="mt-1 text-xs leading-5 text-slate-400">
                    Your campaign is currently active. Contributions are
                    accepted until the campaign deadline.
                  </p>
                </div>

                <div className="mt-4 grid grid-cols-2 gap-3">
                  <div className="rounded-xl bg-[#0d131d] p-3">
                    <p className="text-xs text-slate-500">
                      Platform fees
                    </p>

                    <p className="mt-1 font-semibold text-white">
                      {formatEther(fees)} ETH
                    </p>
                  </div>

                  <div className="rounded-xl bg-[#0d131d] p-3">
                    <p className="text-xs text-slate-500">
                      Withdrawn
                    </p>

                    <p className="mt-1 font-semibold text-white">
                      {formatEther(withdrawn)} ETH
                    </p>
                  </div>
                </div>

                {secondsLeft === 0 && (
                  <button
                    onClick={handleFinalize}
                    disabled={busy || !correctNetwork}
                    className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-[#a855f7] py-3 font-semibold text-white transition hover:bg-[#9333ea]"
                  >
                    Finalize campaign
                    <ArrowUpRight size={17} />
                  </button>
                )}
              </div>
            )}

            {/* OWNER: SUCCESSFUL CAMPAIGN */}

            {isOwner && campaignState === 1 && (
              <div className="mt-5">
                <div className="rounded-xl border border-emerald-400/20 bg-emerald-400/5 p-4">
                  <p className="text-sm font-semibold text-emerald-400">
                    Campaign successful
                  </p>

                  <p className="mt-1 text-xs leading-5 text-slate-400">
                    The funding goal has been reached. You can now withdraw
                    available campaign funds.
                  </p>
                </div>

                <label className="mt-4 block text-sm text-slate-400">
                  Withdrawal amount
                </label>

                <div className="mt-2 flex items-center rounded-xl border border-slate-700 bg-[#0d131d] px-4 focus-within:border-[#2ebac6]">
                  <input
                    value={withdrawAmount}
                    onChange={(event) => setWithdrawAmount(event.target.value)}
                    type="number"
                    min="0"
                    step="any"
                    placeholder="Full balance if empty"
                    className="w-full bg-transparent py-3 text-sm text-white outline-none"
                  />

                  <span className="text-sm text-slate-400">
                    ETH
                  </span>
                </div>

                <button
                  onClick={handleWithdraw}
                  disabled={busy || !correctNetwork}
                  className="mt-3 flex w-full items-center justify-center gap-2 rounded-xl bg-[#159f91] py-3 font-semibold text-white transition hover:bg-[#2ebac6]"
                >
                  <ArrowDownToLine size={17} />
                  Withdraw funds
                </button>

                <div className="mt-4 grid grid-cols-2 gap-3 text-xs">
                  <div className="rounded-xl bg-[#0d131d] p-3">
                    <p className="text-slate-500">Platform fees</p>
                    <p className="mt-1 font-semibold text-white">
                      {formatEther(fees)} ETH
                    </p>
                  </div>

                  <div className="rounded-xl bg-[#0d131d] p-3">
                    <p className="text-slate-500">Owner withdrawals</p>
                    <p className="mt-1 font-semibold text-white">
                      {formatEther(withdrawn)} ETH
                    </p>
                  </div>
                </div>
              </div>
            )}

            {/* CONTRIBUTOR: FAILED CAMPAIGN */}

            {campaignState === 2 && (
              <div className="mt-5">
                <div className="rounded-xl border border-red-400/20 bg-red-400/5 p-4">
                  <p className="text-sm font-semibold text-red-400">
                    Campaign failed
                  </p>

                  <p className="mt-1 text-xs leading-5 text-slate-400">
                    The campaign did not reach its funding goal.
                    Eligible contributors can claim their refunds.
                  </p>
                </div>

                {isConnected && contribution > 0n ? (
                  <button
                    onClick={handleRefund}
                    disabled={busy || !correctNetwork}
                    className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-amber-500 py-3 font-semibold text-black transition hover:bg-amber-400"
                  >
                    Claim your refund
                    <ArrowUpRight size={17} />
                  </button>
                ) : (
                  <p className="mt-4 text-sm text-slate-500">
                    No refundable contribution found for this wallet.
                  </p>
                )}
              </div>
            )}

            {/* NON-OWNER */}

            {!isOwner && campaignState !== 2 && (
              <div className="mt-5 rounded-xl border border-slate-700/60 bg-[#0d131d] p-4">
                <div className="flex items-center gap-2 text-sm font-medium text-slate-300">
                  <LockKeyhole size={16} className="text-[#a855f7]" />
                  Restricted owner controls
                </div>

                <p className="mt-2 text-xs leading-5 text-slate-500">
                  Administrative actions are available only to the
                  campaign owner. Your contribution remains independently
                  recorded on-chain.
                </p>
              </div>
            )}

          </div>
        </section>

        {/* TRANSACTION STATUS */}

        <section className="app-status rounded-xl border border-slate-700/70 bg-[#111722] px-5 py-3">

          <h3 className="text-sm font-semibold text-white">
            Transaction status
          </h3>

          {loading && (
            <p className="flex items-center gap-2 text-xs text-slate-400">
              <LoaderCircle size={15} className="animate-spin" />
              Loading campaign data...
            </p>
          )}

          {notice && (
            <p className="flex items-center gap-2 text-xs text-[#39c6a5]">
              <CheckCircle2 size={15} />
              {notice}
            </p>
          )}

          {busy && (
            <p className="flex items-center gap-2 text-xs text-[#c084fc]">
              <LoaderCircle size={15} className="animate-spin" />
              {confirming
                ? 'Waiting for block confirmation...'
                : 'Waiting for wallet transaction...'}
            </p>
          )}

          {error && (
            <p className="flex items-center gap-2 break-all text-xs text-red-400">
              <XCircle size={15} />
              {error}
            </p>
          )}

          {txHash && (
            <a
              href={`https://sepolia.etherscan.io/tx/${txHash}`}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1 text-xs text-[#c084fc] hover:text-white"
            >
              View transaction
              <ExternalLink size={13} />
            </a>
          )}

          {!loading && !notice && !busy && !error && !txHash && (
            <span className="text-xs text-slate-500">
              No recent transaction activity.
            </span>
          )}
        </section>

        {/* FOOTER */}

        <footer className="app-footer flex flex-wrap items-center justify-between gap-3 border-t border-slate-800 py-3 text-xs text-slate-500">

          <p>
            Secure Crowdfunding Protocol · Built on Ethereum
          </p>

          <a
            href={explorer}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-2 transition hover:text-white"
          >
            Contract on Etherscan
            <ExternalLink size={13} />
          </a>

        </footer>
      </div>

      {/* WALLET CONNECTION NOTICE */}

      {!isConnected && (
        <div className="fixed bottom-4 left-1/2 z-50 -translate-x-1/2 rounded-xl border border-slate-700 bg-[#141c29] px-5 py-3 text-center text-xs text-slate-300 shadow-xl">
          Connect your wallet to interact with the campaign.
        </div>
      )}

      {/* NETWORK SWITCH NOTICE */}

      {isConnected && !correctNetwork && (
        <div className="fixed bottom-4 left-1/2 z-50 flex -translate-x-1/2 flex-wrap items-center justify-center gap-3 rounded-xl border border-amber-400/20 bg-[#141c29] px-5 py-3 shadow-xl">

          <span className="text-sm text-amber-300">
            Switch to Sepolia to continue.
          </span>

          <button
            onClick={() => switchChain({ chainId: SEPOLIA_CHAIN_ID })}
            className="rounded-lg bg-amber-500 px-3 py-2 text-xs font-semibold text-black transition hover:bg-amber-400"
          >
            Switch network
          </button>
        </div>
      )}

    </main>
  )
}

export default App
