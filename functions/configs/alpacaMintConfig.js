import fs from 'fs';
import { Location, ReturnType, CodeLanguage } from '@chainlink/functions-toolkit';

const requestConfig = {
    source: fs.readFileSync('functions/simulators/alpacaBalance.js').toString(),
    codeLocation: Location.Inline,
    secrets: { alpacaKey: process.env.ALPACA_API_KEY, alpacaSecret: process.env.ALPACA_API_SECRET },
    secretsLocation: Location.DONHosted,
    args: [],
    CodeLanguage: CodeLanguage.JavaScript,
    expectedReturnType: ReturnType.uint256,
};


module.exports = requestConfig;