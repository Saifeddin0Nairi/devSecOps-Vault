package com.example.democyber;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

/**
 * GET / is public. GET /api/secure needs the header X-API-Key with the configured "api-key".
 * The key is never logged and never kept in clear text: only its SHA-256 hash stays in memory.
 */
@RestController
public class DemocyberController {

    static final String API_KEY_HEADER = "X-API-Key";

    /** SHA-256 of the configured key, or null when no key is configured. */
    private final byte[] expectedKeyHash;

    public DemocyberController(@Value("${api-key:}") String apiKey) {
        this.expectedKeyHash = apiKey.isBlank() ? null : sha256(apiKey);
    }

    @GetMapping("/")
    public String home() {
        return "Hello from Democyber Vault!";
    }

    @GetMapping("/api/secure")
    public ResponseEntity<String> secure(
            @RequestHeader(name = API_KEY_HEADER, required = false) String providedKey) {
        if (!isValid(providedKey)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok("Access granted: the API key is valid.");
    }

    private boolean isValid(String providedKey) {
        // Fail closed: no configured key, or no key in the request, means no access.
        if (expectedKeyHash == null || providedKey == null) {
            return false;
        }
        // Constant-time comparison of two hashes of the same length: the answer time
        // does not depend on how many characters match, nor on the key length.
        return MessageDigest.isEqual(expectedKeyHash, sha256(providedKey));
    }

    private static byte[] sha256(String value) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is not available", e);
        }
    }

}
