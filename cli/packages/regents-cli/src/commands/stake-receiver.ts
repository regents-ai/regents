import { getFlag, type ParsedCliArgs } from "../parse.js";

const evmAddressPattern = /^0x[0-9a-fA-F]{40}$/u;

export const stakeReceiverFlag = (args: ParsedCliArgs): string | undefined => {
  const value = getFlag(args, "receiver");
  if (value === undefined) {
    return undefined;
  }

  const receiver = value.trim();
  if (!evmAddressPattern.test(receiver)) {
    throw new Error("--receiver must be a 0x address with 40 hex characters.");
  }

  return receiver.toLowerCase();
};

export const stakeBody = (
  amount: string,
  receiver: string | undefined,
): { amount: string; receiver?: string } =>
  receiver === undefined ? { amount } : { amount, receiver };
