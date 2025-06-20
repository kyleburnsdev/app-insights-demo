package com.example.customerservice.controller;

import com.microsoft.applicationinsights.TelemetryClient;
import org.springframework.http.HttpHeaders;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/customers")
public class CustomerController {
    private final TelemetryClient telemetryClient = new TelemetryClient();

    // Intentional flaw: throws exception for negative customerId
    @GetMapping("/{id}")
    public Map<String, Object> getCustomer(@PathVariable int id, @RequestHeader HttpHeaders headers) {
        String userId = headers.getFirst("X-User-Id");
        if (userId == null) userId = "anonymous";
        String correlationId = headers.getFirst("Request-Id");
        if (correlationId == null) correlationId = UUID.randomUUID().toString();
        telemetryClient.trackEvent("CustomerLookupRequested", Map.of("userId", userId, "correlationId", correlationId), null);
        try {
            if (id < 0) {
                throw new IllegalArgumentException("Customer ID cannot be negative");
            }
            // Simulate customer data
            Map<String, Object> customer = new HashMap<>();
            customer.put("id", id);
            customer.put("firstName", "Demo");
            customer.put("lastName", "User");
            customer.put("email", "demo.user@example.com");
            telemetryClient.trackEvent("CustomerLookupSuccess", Map.of("userId", userId, "correlationId", correlationId), null);
            telemetryClient.trackMetric("CustomerLookupSuccess", 1.0);
            return customer;
        } catch (Exception ex) {
            telemetryClient.trackEvent("CustomerLookupError", Map.of("userId", userId, "correlationId", correlationId, "error", ex.getMessage()), null);
            telemetryClient.trackMetric("CustomerLookupError", 1.0);
            telemetryClient.trackException(ex);
            throw ex;
        }
    }
}
