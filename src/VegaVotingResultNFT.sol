// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title VegaVotingResultNFT
 * @notice ERC-721 NFT that encapsulates the results of a finalized vote.
 * @dev Only the governance contract (set as owner) can mint.
 */
contract VegaVotingResultNFT is ERC721, Ownable {
    using Strings for uint256;
    using Strings for bytes32;

    uint256 private _nextTokenId;

    struct VoteResult {
        bytes32 votingId;
        string description;
        uint256 yesVotes;
        uint256 noVotes;
        bool passed;
        uint256 finalizedAt;
    }

    /// @notice tokenId => vote result
    mapping(uint256 => VoteResult) public voteResults;

    constructor(address governance) ERC721("VegaVoteResult", "VVR") Ownable(governance) {}

    /**
     * @notice Mint a result NFT to `to` with the vote data.
     * @return tokenId The minted token ID.
     */
    function mintResult(
        address to,
        bytes32 votingId,
        string calldata description,
        uint256 yesVotes,
        uint256 noVotes,
        bool passed,
        uint256 finalizedAt
    ) external onlyOwner returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        voteResults[tokenId] = VoteResult({
            votingId: votingId,
            description: description,
            yesVotes: yesVotes,
            noVotes: noVotes,
            passed: passed,
            finalizedAt: finalizedAt
        });
    }

    /**
     * @notice On-chain SVG metadata for the NFT.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        VoteResult storage r = voteResults[tokenId];

        string memory status = r.passed ? "PASSED" : "REJECTED";
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300">',
                '<rect width="400" height="300" fill="#1a1a2e"/>',
                '<text x="20" y="40" fill="#e94560" font-size="20" font-family="monospace">Vega Vote Result</text>',
                '<text x="20" y="80" fill="#fff" font-size="14" font-family="monospace">Status: ', status, '</text>',
                '<text x="20" y="110" fill="#fff" font-size="14" font-family="monospace">Yes: ', r.yesVotes.toString(), '</text>',
                '<text x="20" y="140" fill="#fff" font-size="14" font-family="monospace">No: ', r.noVotes.toString(), '</text>',
                '<text x="20" y="170" fill="#fff" font-size="14" font-family="monospace">Token #', tokenId.toString(), '</text>',
                '</svg>'
            )
        );

        string memory json = string(
            abi.encodePacked(
                '{"name":"Vega Vote #', tokenId.toString(),
                '","description":"', r.description,
                '","image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)),
                '","attributes":[{"trait_type":"Status","value":"', status,
                '"},{"trait_type":"Yes Votes","value":', r.yesVotes.toString(),
                '},{"trait_type":"No Votes","value":', r.noVotes.toString(), '}]}'
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }
}
