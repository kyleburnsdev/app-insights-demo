package com.example.customerservice.controller;

import org.springframework.retry.annotation.Retryable;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import java.util.*;

@RestController
@RequestMapping("/api/customers")
public class CustomerController {
    // Intentional flaw: throws exception for negative customerId
    @GetMapping("/{id}")
    @Retryable(maxAttempts = 3, backoff = @org.springframework.retry.annotation.Backoff(delay = 1000, multiplier = 2.0))
    public Map<String, Object> getCustomer(@PathVariable int id) {
        if (id < 0) {
            throw new IllegalArgumentException("Customer ID cannot be negative");
        }
        // Simulate customer data
        Map<String, Object> customer = new HashMap<>();
        customer.put("id", id);
        customer.put("firstName", "Demo");
        customer.put("lastName", "User");
        customer.put("email", "demo.user@example.com");
        return customer;
    }
}
