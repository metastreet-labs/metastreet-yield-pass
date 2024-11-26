import { ethers } from "ethers";
import axios from "axios";
import { config } from "dotenv";
config();

async function signMessage(privateKey: string): Promise<string> {
  const message = "aethir-batch-claim";
  let wallet = new ethers.Wallet(privateKey);

  let flatSig = await wallet.signMessage(message);
  return flatSig;
}

async function fetchApiToken(ak: string, sk: string, baseUrl: string): Promise<string> {
  const url = `${baseUrl}/console-api/v2/query/getQueryToken?ak=${ak}&sk=${sk}`;

  const response = await axios.get(url);

  if (response.data.code !== 135000) {
    throw new Error(`Failed to fetch API token: ${response.data.msg}`);
  }

  return response.data.data.token;
}

async function claimTokens(
  baseUrl: string,
  token: string,
  privateKey: string,
  amount: string,
  claimType: number
): Promise<void> {
  const signature = signMessage(privateKey);
  const url = `${baseUrl}/console-api/v2/query/claim`;
  const headers = { Authorization: token };
  const payload = {
    signature,
    athForm: amount,
    type: claimType, // 1 for 30 days (25%), 2 for 180 days (100%)
  };

  const response = await axios.post(url, payload, { headers });

  if (response.data.code !== 135000) {
    throw new Error(`Failed to claim tokens: ${response.data.msg}`);
  }

  console.log("Claim successful:", response.data.data);
}

async function withdrawTokens(baseUrl: string, token: string, privateKey: string, amount: string): Promise<void> {
  const signature = signMessage(privateKey);

  const url = `${baseUrl}/console-api/v2/query/withdraw`;
  const headers = { Authorization: token };
  const payload = {
    signature,
    athForm: amount,
  };

  const response = await axios.post(url, payload, { headers });

  if (response.data.code !== 135000) {
    throw new Error(`Failed to withdraw tokens: ${response.data.msg}`);
  }

  console.log("Withdraw successful:", response.data.data);
}

(async () => {
  const baseUrl = "https://pre-app.aethir.com/";
  const ak = process.env.AETHIR_ACCESS_KEY;
  const sk = process.env.AETHIR_SECRET_KEY;
  const privateKey = process.env.NODEFI_SIGNING_PRIVATE_KEY;
  const claimAmount = "0"; // Amount to claim
  const withdrawAmount = "0"; // Amount to withdraw
  const claimType = 2; // 1: 30 days, 2: 180 days
  const isClaim = true; // false for withdraw

  try {
    // Fetch API Token
    const token = await fetchApiToken(ak!, sk!, baseUrl);

    if (isClaim) {
      await claimTokens(baseUrl, token, privateKey!, claimAmount, claimType);
    } else {
      await withdrawTokens(baseUrl, token, privateKey!, withdrawAmount);
    }
  } catch (error: unknown) {
    console.log("error:", error);
    if (error instanceof Error) {
      console.error("Error:", error.message);
    } else {
      console.error("Error:", error);
    }
  }
})();
