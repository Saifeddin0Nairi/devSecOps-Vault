package com.example.democyber;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

/** Fail closed: when no API key is configured, /api/secure refuses everything. */
@WebMvcTest(controllers = DemocyberController.class, properties = "api-key=")
class DemocyberControllerNoKeyTest {

    @Autowired
    private MockMvcTester mvc;

    @Test
    void secureRefusesEverythingWhenNoKeyIsConfigured() {
        assertThat(mvc.get().uri("/api/secure"))
                .hasStatus(HttpStatus.UNAUTHORIZED);
        // An empty key must not match an empty configuration
        assertThat(mvc.get().uri("/api/secure").header(DemocyberController.API_KEY_HEADER, ""))
                .hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(mvc.get().uri("/api/secure").header(DemocyberController.API_KEY_HEADER, "any-key"))
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

}
