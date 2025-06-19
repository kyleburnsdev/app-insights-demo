-- Seed data for mortgageappdb
-- Customers
INSERT INTO Customers (CustomerId, FirstName, LastName, Email) VALUES
  (1, 'Alice', 'Smith', 'alice.smith@example.com'),
  (2, 'Bob', 'Johnson', 'bob.johnson@example.com');

-- Loans
INSERT INTO Loans (LoanId, CustomerId, Amount, Status) VALUES
  (1001, 1, 250000, 'Pending'),
  (1002, 2, 320000, 'Approved');

-- Seed thousands of customers
WITH Numbers AS (
    SELECT TOP (2000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
)
INSERT INTO Customers (CustomerId, FirstName, LastName, Email)
SELECT n, CONCAT('First', n), CONCAT('Last', n), CONCAT('user', n, '@example.com')
FROM Numbers;

-- Seed thousands of loans
WITH LoanNumbers AS (
    SELECT TOP (5000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
)
INSERT INTO Loans (LoanId, CustomerId, Amount, Status)
SELECT 10000 + n, 1 + (n % 2000), 100000 + (n * 1000) % 500000, 
    CASE WHEN n % 3 = 0 THEN 'Pending' WHEN n % 3 = 1 THEN 'Approved' ELSE 'Rejected' END
FROM LoanNumbers;
