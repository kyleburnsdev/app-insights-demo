package com.example.customerservice;

import com.microsoft.applicationinsights.attach.ApplicationInsights;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class CustomerServiceApplication {
    public static void main(String[] args) {
        // Attach Application Insights using connection string from env
        String aiConnStr = System.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING");
        if (aiConnStr != null && !aiConnStr.isEmpty()) {
            System.setProperty("APPLICATIONINSIGHTS_CONNECTION_STRING", aiConnStr);
            ApplicationInsights.attach();
        }
        SpringApplication.run(CustomerServiceApplication.class, args);
    }
}
