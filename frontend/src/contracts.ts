
import type { Abi, Address } from 'viem'
import fundMeJson from './contracts/FundMe.abi.json'

export const FUNDME_ADDRESS = import.meta.env
  .VITE_FUNDME_ADDRESS as Address

export const FUNDME_ABI = fundMeJson as Abi

export const SEPOLIA_CHAIN_ID = 11155111
