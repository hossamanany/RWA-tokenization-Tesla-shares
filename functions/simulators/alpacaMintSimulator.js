import { requestConfig } from "../configs/alpacaMintConfig.js";
import { SimulateScript, decodeResult } from '@chainlink/functions-toolkit';

async function main() {
    const { responseBytesHexstring, errorString, } = await SimulateScript(requestConfig);
    if (responseBytesHexstring) {
        console.log(`Response returned by script: ${decodeResult(responseBytesHexstring, requestConfig.expectedReturnType).toString()}\n`);
    }
    if (errorString) {
        console.error(`Error returned by script: ${errorString}\n`);
    }
};

main().catch((error) => {
    console.error(error);
    Process.exit(1);
});