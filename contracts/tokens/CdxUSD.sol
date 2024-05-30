// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OFTExtended} from "./OFTExtended.sol";
import {ICdxUSD} from "contracts/interfaces/ICdxUSD.sol";

// ======================= Errors ================================

error CdxUSD__ONLY_GUARDIAN();
error CdxUSD__BRIDGING_LIMIT_REACHED(uint32 _eid);
error CdxUSD__BRIDGING_HOURLY_LIMIT_REACHED(uint32 _eid);
error CdxUSD__BRIDGING_PAUSED();

/**
 * @title CdxUSD Contract
 * @dev CdxUSD is a LZ OFT token that extends the functionality of the OFT contract.
 */
contract CdxUSD is ICdxUSD, OFTExtended {
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        address _treasury,
        address _guardian
    ) OFTExtended(_name, _symbol, _lzEndpoint, _delegate, _treasury, _guardian) {}
}
