import Darwin
import Foundation

/// Import only a bounded regular file. The caller supplies the full reviewed canonical digest.
public enum LocalReviewFile {
    public static func load(_ path: URL, domain: ExperimentDomain,
                            binaries: CandidateExperimentPlan.Binaries, expectedSHA256: String) throws -> LocalApprovalReview {
        guard path.path.hasPrefix("/"), path.standardizedFileURL.resolvingSymlinksInPath().path == path.standardizedFileURL.path else {
            throw LocalApprovalError.reviewMismatch
        }
        let fd = open(path.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw LocalApprovalError.reviewMissing }
        defer { close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_nlink == 1, attributes.st_size > 0, attributes.st_size <= 16_384 else {
            throw LocalApprovalError.reviewMismatch
        }
        var bytes = [UInt8](repeating: 0, count: 16_385), size = 0
        while size < bytes.count {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: size), $0.count - size) }
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw LocalApprovalError.reviewMismatch }
            size += count
        }
        guard size <= 16_384 else { throw LocalApprovalError.reviewMismatch }
        let review = try JSONDecoder().decode(LocalApprovalReview.self, from: Data(bytes.prefix(size)))
        try review.validate(domain: domain, binaries: binaries)
        guard try review.sha256() == expectedSHA256 else { throw LocalApprovalError.reviewMismatch }
        return review
    }
}
