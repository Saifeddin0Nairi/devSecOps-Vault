package com.example.democyber;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

/** Web tests with an API key configured (a fake value, for tests only). */
@WebMvcTest(controllers = DemocyberController.class, properties = "api-key=" + DemocyberControllerTest.TEST_KEY)
class DemocyberControllerTest {

    static final String TEST_KEY = "test-only-key";

    @Autowired
    private MockMvcTester mvc;

    @Test
    void homeIsPublic() {
        assertThat(mvc.get().uri("/"))
                .hasStatus(HttpStatus.INTERNAL_SERVER_ERROR)
                .hasBodyTextEqualTo("Broken on purpose (smoke test demo)");
    }

    @Test
    void secureWithoutKeyIsRejected() {
        assertThat(mvc.get().uri("/api/secure"))
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void secureWithWrongKeyIsRejected() {
        assertThat(mvc.get().uri("/api/secure").header(DemocyberController.API_KEY_HEADER, "wrong-key"))
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void secureWithRightKeyIsAccepted() {
        assertThat(mvc.get().uri("/api/secure").header(DemocyberController.API_KEY_HEADER, TEST_KEY))
                .hasStatusOk();
    }

}
