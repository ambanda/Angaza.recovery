-- Add foreign key constraint from accounts to organizations
ALTER TABLE accounts
ADD CONSTRAINT FK_accounts_organizations
FOREIGN KEY (organization_id)
REFERENCES organizations (ID);

 ---Add foreign key constraint from accounts to groups
ALTER TABLE accounts
ADD CONSTRAINT FK_accounts_groups
FOREIGN KEY (group_id)
REFERENCES groups (ID);

-- Add foreign key constraint from accounts to billings
ALTER TABLE accounts
ADD CONSTRAINT FK_accounts_billings
FOREIGN KEY (billing_id)
REFERENCES billings (ID);

--Identify the rows in the "accounts" table that violate the foreign key constraint in Billings table
SELECT *
FROM accounts
WHERE billing_id NOT IN (SELECT ID FROM billings)

--Fill missing row in billings that is not in accounts ID
INSERT INTO billings (ID,CREATED_WHEN,IS_POSTPAID,PRICE_UPFRONT,VALUE_DIVISOR,PRICE_UNLOCK,DOWN_PAYMENT_PERIOD)
VALUES(3135554,'2022-06-18 07:14:45.887000000','false',7800,1,45285,'{   "days": 7,   "hours": 0,   "minutes": 0,   "months": 0,   "seconds": 0,   "years": 0 }' )
SELECT DISTINCT billing_id
FROM accounts
WHERE billing_id NOT IN (SELECT ID FROM billings)

-- Add foreign key constraint from groups to products
ALTER TABLE groups
ADD CONSTRAINT FK_groups_products
FOREIGN KEY (product_id)
REFERENCES products (ID);


-- Add foreign key constraint from payments to accounts
ALTER TABLE payments
ADD CONSTRAINT FK_payments_accounts
FOREIGN KEY (account_id)
REFERENCES accounts (ID);

-- Add foreign key constraint from payments to receipts
ALTER TABLE payments
ADD CONSTRAINT FK_payments_receipts
FOREIGN KEY (receipt_id)
REFERENCES receipts (ID);



select *from Accounts

---drop fk constraints
ALTER TABLE payments
DROP CONSTRAINT FK_payments_receipts

--check fk contraints 
SELECT *
FROM information_schema.TABLE_CONSTRAINTS
WHERE table_schema = '<FK_payments_receipts>'
AND table_name = '<payments>'





------------
------------
------------
--Calculate OCR per account 

WITH AccountDetails AS (
    SELECT
        a.ID AS AccountID,
        b.price_unlock AS PriceUnlock,
        a.nominal_term AS NominalTerm,
        CAST(JSON_VALUE(a.nominal_term, '$.years') AS int) * 365
        + CAST(JSON_VALUE(a.nominal_term, '$.months') AS int) * 30
        + CAST(JSON_VALUE(a.nominal_term, '$.days') AS int) AS NominalTermInDays,
        r.Amount AS AmountPaid,
        a.registration_date AS RegistrationDate,
        a.payment_due_date AS PaymentDueDate
    FROM
        accounts a
        JOIN billings b ON a.billing_id = b.ID
        LEFT JOIN payments p ON a.ID = p.account_id
        LEFT JOIN receipts r ON p.receipt_id = r.ID
),
DueAmounts AS (
    SELECT
        AccountID,
        PriceUnlock / CAST(NominalTermInDays AS float) AS DailyDueAmount,
        DATEDIFF(DAY, RegistrationDate, PaymentDueDate) AS DaysSinceRegistration
    FROM
        AccountDetails
),
TotalAmounts AS (
    SELECT
        AccountID,
        SUM(ISNULL(AmountPaid, 0)) AS TotalAmountPaid
    FROM
        AccountDetails
    GROUP BY
        AccountID
),
TotalDueAmounts AS (
    SELECT
        AccountID,
        DailyDueAmount * DaysSinceRegistration AS TotalDueAmount
    FROM
        DueAmounts
)
SELECT
    d.AccountID,
    COALESCE((t.TotalAmountPaid / d.TotalDueAmount) * 100, 0) AS OCR
FROM
    TotalDueAmounts d
    LEFT JOIN TotalAmounts t ON d.AccountID = t.AccountID;


	--------------
	--------------
	--Calculate OCR by Month


-----------------------------	
----------------------------
----------------------------

WITH AccountDetails AS (
    SELECT
        a.ID AS AccountID,
        YEAR(a.registration_date) AS RegistrationYear,
        MONTH(a.registration_date) AS RegistrationMonth,
        CAST(a.registration_date AS datetime2) AS RegistrationDate,
        CAST(JSON_VALUE(b.down_payment_period, '$.days') AS int) AS DownPaymentPeriod,
        b.price_unlock AS PriceUnlock,
        CAST(JSON_VALUE(a.nominal_term, '$.days') AS int) AS NominalTermInDays,
        p.receipt_id AS ReceiptID,
        r.amount AS AmountPaid,
        CAST(r.effective_when AS datetime2) AS PaymentDate
    FROM
        accounts a
        JOIN billings b ON a.billing_id = b.ID
        LEFT JOIN payments p ON a.ID = p.account_id
        LEFT JOIN receipts r ON p.receipt_id = r.ID
),
AmountPaidPerAccount AS (
    SELECT
        AccountID,
        RegistrationYear,
        RegistrationMonth,
        SUM(AmountPaid) AS AmountPaid
    FROM
        AccountDetails
    GROUP BY
        AccountID,
        RegistrationYear,
        RegistrationMonth
),
AmountDuePerAccount AS (
    SELECT
        AccountID,
        RegistrationYear,
        RegistrationMonth,
        PriceUnlock * 
        (DATEDIFF(DAY, RegistrationDate, GETDATE()) - DownPaymentPeriod) / 
        (NominalTermInDays * 1.0) AS AmountDue
    FROM
        AccountDetails
),
CombinedAmounts AS (
    SELECT
        p.AccountID,
        p.RegistrationYear,
        p.RegistrationMonth,
        p.AmountPaid,
        d.AmountDue
    FROM
        AmountPaidPerAccount p
        JOIN AmountDuePerAccount d ON p.AccountID = d.AccountID AND p.RegistrationYear = d.RegistrationYear AND p.RegistrationMonth = d.RegistrationMonth
)
SELECT
    RegistrationYear,
    RegistrationMonth,
    SUM(AmountPaid) / SUM(AmountDue) * 100 AS OCR
FROM
    CombinedAmounts
GROUP BY
    RegistrationYear,
    RegistrationMonth
ORDER BY
    RegistrationYear,
    RegistrationMonth;

----------------
---------------
----First Payment On Time on account basis 

WITH AccountDetails AS (
    SELECT
        a.ID AS AccountID,
        CAST(a.registration_date AS datetime2) AS RegistrationDate,
        CAST(JSON_VALUE(b.down_payment_period, '$.days') AS int) AS DownPaymentPeriod,
        b.price_unlock AS PriceUnlock,
        CAST(JSON_VALUE(a.nominal_term, '$.days') AS int) AS NominalTermInDays,
        p.receipt_id AS ReceiptID,
        r.amount AS AmountPaid,
        CAST(r.effective_when AS datetime2) AS PaymentDate
    FROM
        accounts a
        JOIN billings b ON a.billing_id = b.ID
        LEFT JOIN payments p ON a.ID = p.account_id
        LEFT JOIN receipts r ON p.receipt_id = r.ID
),
FirstPayments AS (
    SELECT
        AccountID,
        MIN(PaymentDate) AS FirstPaymentDate
    FROM
        AccountDetails
    WHERE
        AmountPaid IS NOT NULL
    GROUP BY
        AccountID
),
ExpectedFirstPaymentDate AS (
    SELECT
        AccountID,
        DATEADD(DAY, DownPaymentPeriod, RegistrationDate) AS ExpectedPaymentDate
    FROM
        AccountDetails
)
SELECT
    e.AccountID,
    CASE
        WHEN f.FirstPaymentDate <= e.ExpectedPaymentDate THEN 1
        ELSE 0
    END AS FirstPaymentOnTime
FROM
    ExpectedFirstPaymentDate e
    LEFT JOIN FirstPayments f ON e.AccountID = f.AccountID;

-----------
-------------
--First Payment On Time on Monthly basis

WITH AccountDetails AS (
    SELECT
        a.ID AS AccountID,
        CAST(a.registration_date AS datetime2) AS RegistrationDate,
        CAST(JSON_VALUE(b.down_payment_period, '$.days') AS int) AS DownPaymentPeriod,
        b.price_unlock AS PriceUnlock,
        CAST(JSON_VALUE(a.nominal_term, '$.days') AS int) AS NominalTermInDays,
        p.receipt_id AS ReceiptID,
        r.amount AS AmountPaid,
        CAST(r.effective_when AS datetime2) AS PaymentDate
    FROM
        accounts a
        JOIN billings b ON a.billing_id = b.ID
        LEFT JOIN payments p ON a.ID = p.account_id
        LEFT JOIN receipts r ON p.receipt_id = r.ID
),
FirstPayments AS (
    SELECT
        AccountID,
        MIN(PaymentDate) AS FirstPaymentDate
    FROM
        AccountDetails
    WHERE
        AmountPaid IS NOT NULL
    GROUP BY
        AccountID
),
ExpectedFirstPaymentDate AS (
    SELECT
        AccountID,
        DATEADD(DAY, DownPaymentPeriod, RegistrationDate) AS ExpectedPaymentDate
    FROM
        AccountDetails
),
FirstPaymentOnTime AS (
    SELECT
        e.AccountID,
        YEAR(e.ExpectedPaymentDate) AS RegistrationYear,
        MONTH(e.ExpectedPaymentDate) AS RegistrationMonth,
        CASE
            WHEN f.FirstPaymentDate <= e.ExpectedPaymentDate THEN 1
            ELSE 0
        END AS FirstPaymentOnTime
    FROM
        ExpectedFirstPaymentDate e
        LEFT JOIN FirstPayments f ON e.AccountID = f.AccountID
)
SELECT
    RegistrationYear,
    RegistrationMonth,
    COUNT(*) AS TotalAccounts,
    SUM(FirstPaymentOnTime) AS OnTimePayments,
    CAST(SUM(FirstPaymentOnTime) AS float) / CAST(COUNT(*) AS float) * 100 AS FirstPaymentOnTimePercentage
FROM
    FirstPaymentOnTime
GROUP BY
    RegistrationYear,
    RegistrationMonth
ORDER BY
    RegistrationYear,
    RegistrationMonth;


-----------
--------------








