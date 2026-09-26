CREATE DATABASE IF NOT EXISTS StoreDB;
USE StoreDB;

-- 1. Verify table row counts across warehouse entities
SELECT 'Customers' AS Table_Name, COUNT(*) AS Record_Count FROM Customers
UNION ALL
SELECT 'Orders', COUNT(*) FROM Orders
UNION ALL
SELECT 'Order_Items', COUNT(*) FROM Order_Items;

-- 2. Detect duplicate line items within the same order
WITH DuplicateLineItems AS (
    SELECT 
        item_id,
        order_id,
        product_name,
        quantity,
        unit_price,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, product_name 
            ORDER BY item_id
        ) AS row_occurrence
    FROM Order_Items
)
SELECT * 
FROM DuplicateLineItems
WHERE row_occurrence > 1;

-- 3. Delete duplicate product entries while retaining initial record
DELETE FROM Order_Items
WHERE item_id IN (
    SELECT item_id FROM (
        SELECT 
            item_id,
            ROW_NUMBER() OVER (
                PARTITION BY order_id, product_name 
                ORDER BY item_id
            ) AS row_occurrence
        FROM Order_Items
    ) temp
    WHERE temp.row_occurrence > 1
);

-- 4. Check for orphaned orders lacking a registered customer
SELECT o.order_id, o.customer_id
FROM Orders o
LEFT JOIN Customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- 5. Audit records for zero or negative values
SELECT * 
FROM Order_Items
WHERE quantity <= 0 OR unit_price <= 0;

-- 6. Compute executive KPIs: Total orders, units, revenue, and AOV
SELECT 
    COUNT(DISTINCT o.order_id) AS total_orders_placed,
    SUM(oi.quantity) AS total_units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS gross_revenue,
    ROUND(SUM(oi.quantity * oi.unit_price) / COUNT(DISTINCT o.order_id), 2) AS average_order_value
FROM Orders o
INNER JOIN Order_Items oi 
    ON o.order_id = oi.order_id;

-- 7. Rank VIP customers by total revenue and order volume
SELECT  
    c.customer_id,
    c.customer_name,
    c.city,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_spent
FROM Customers c
INNER JOIN Orders o ON c.customer_id = o.customer_id
INNER JOIN Order_Items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.customer_name, c.city
ORDER BY total_spent DESC;

-- 8. Identify inactive registered customers with zero orders
SELECT 
    c.customer_id,
    c.customer_name,
    c.city
FROM Customers c
LEFT JOIN Orders o ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL;

-- 9. Segment customer spend tiers for targeted CRM campaigns
WITH CustomerSpend AS (
    SELECT 
        c.customer_id,
        c.customer_name,
        c.city,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_spent
    FROM Customers c
    INNER JOIN Orders o ON c.customer_id = o.customer_id
    INNER JOIN Order_Items oi ON o.order_id = oi.order_id
    GROUP BY c.customer_id, c.customer_name, c.city
)
SELECT 
    customer_id,
    customer_name,
    city,
    total_orders,
    total_spent,
    CASE 
        WHEN total_spent >= 3000 THEN 'Platinum Tier'
        WHEN total_spent BETWEEN 1500 AND 2999.99 THEN 'Gold Tier'
        WHEN total_spent BETWEEN 500 AND 1499.99 THEN 'Silver Tier'
        ELSE 'Bronze Tier'
    END AS customer_tier
FROM CustomerSpend
ORDER BY total_spent DESC;

-- 10. Extract top 5 products by gross sales volume and revenue
SELECT 
    oi.product_name,
    COUNT(DISTINCT oi.order_id) AS total_orders_containing_item,
    SUM(oi.quantity) AS total_units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_revenue
FROM Order_Items oi
GROUP BY oi.product_name
ORDER BY total_revenue DESC
LIMIT 5;

-- 11. Evaluate geographic market share and average spend per client
SELECT 
    c.city,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COUNT(DISTINCT o.order_id) AS total_orders_placed,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_city_revenue,
    ROUND(SUM(oi.quantity * oi.unit_price) / COUNT(DISTINCT c.customer_id), 2) AS avg_revenue_per_customer
FROM Customers c
INNER JOIN Orders o ON c.customer_id = o.customer_id
INNER JOIN Order_Items oi ON o.order_id = oi.order_id
GROUP BY c.city
ORDER BY total_city_revenue DESC;

-- 12. Determine top-spending customer within each city using dense ranking
WITH RankedCityCustomers AS (
    SELECT 
        c.city,
        c.customer_name,
        ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_spent,
        DENSE_RANK() OVER (
            PARTITION BY c.city 
            ORDER BY SUM(oi.quantity * oi.unit_price) DESC
        ) AS rank_in_city
    FROM Customers c
    INNER JOIN Orders o ON c.customer_id = o.customer_id
    INNER JOIN Order_Items oi ON o.order_id = oi.order_id
    GROUP BY c.city, c.customer_id, c.customer_name
)
SELECT 
    city,
    customer_name AS top_customer,
    total_spent
FROM RankedCityCustomers
WHERE rank_in_city = 1
ORDER BY total_spent DESC;

-- 13. Track monthly transaction volume and gross revenue growth
SELECT 
    DATE_FORMAT(o.order_date, '%Y-%m') AS sales_month,
    COUNT(DISTINCT o.order_id) AS monthly_orders,
    SUM(oi.quantity) AS monthly_units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS monthly_revenue
FROM Orders o
INNER JOIN Order_Items oi ON o.order_id = oi.order_id
GROUP BY DATE_FORMAT(o.order_date, '%Y-%m')
ORDER BY sales_month ASC;

-- 14. Build reusable reporting view for BI dashboard integration
CREATE OR REPLACE VIEW vw_customer_order_summary AS
SELECT 
    c.customer_id,
    c.customer_name,
    c.city,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COALESCE(SUM(oi.quantity), 0) AS total_items_purchased,
    COALESCE(ROUND(SUM(oi.quantity * oi.unit_price), 2), 0.00) AS total_lifetime_value,
    MAX(o.order_date) AS latest_order_date
FROM Customers c
LEFT JOIN Orders o ON c.customer_id = o.customer_id
LEFT JOIN Order_Items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.customer_name, c.city;

-- 15. Preview sample records from reporting view
SELECT * FROM vw_customer_order_summary LIMIT 10;