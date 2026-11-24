# Runtime image for democyber. The JAR is built before, by Maven (./mvnw verify).
# Pinned base image: Temurin 21 JRE (no compiler) on Alpine 3.24.
FROM eclipse-temurin:21.0.13.1_2-jre-alpine-3.24

# Non-root user with a fixed UID/GID: no password, no home folder, no login shell.
RUN addgroup -S -g 10001 democyber \
 && adduser -S -D -H -u 10001 -G democyber -s /sbin/nologin democyber

WORKDIR /app

# The JAR belongs to root and is read-only (0444): the app user can run it, not change it.
# .dockerignore sends only target/*.jar to the build, so nothing else can enter the image.
COPY --chown=root:root --chmod=0444 target/*.jar /app/app.jar

USER 10001:10001

# 8080 = application. 8081 = Actuator (management port), never published.
EXPOSE 8080

# Docker checks the app from inside the container, on the management port.
HEALTHCHECK --interval=15s --timeout=3s --start-period=60s --start-interval=2s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8081/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
