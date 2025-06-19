# Stage 1: Build dependencies only when pom.xml changes
FROM maven:3.9.6-eclipse-temurin-17 AS deps
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline

# Stage 2: Build the application
FROM maven:3.9.6-eclipse-temurin-17 AS build
WORKDIR /app
COPY --from=deps /root/.m2 /root/.m2
COPY . .
RUN mvn clean package -DskipTests

# Stage 3: Download Application Insights Java agent
FROM eclipse-temurin:17-jre-focal AS agent
WORKDIR /agent
RUN curl -sSL -o applicationinsights-agent.jar https://github.com/microsoft/ApplicationInsights-Java/releases/download/3.4.17/applicationinsights-agent-3.4.17.jar

# Stage 4: Final runtime image
FROM eclipse-temurin:17-jre-focal
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
COPY --from=agent /agent/applicationinsights-agent.jar ./
EXPOSE 8080
ENV APPLICATIONINSIGHTS_AGENT_FILE=/app/applicationinsights-agent.jar
ENTRYPOINT ["java", "-javaagent:/app/applicationinsights-agent.jar", "-jar", "app.jar"]
