-- USER
-- Technical user managing products and inventory.
-- Soft-delete pattern with is_active + end_date.
CREATE TABLE user (
  id VARCHAR(15) PRIMARY KEY,
  start_date DATETIME(6) NOT NULL,
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  is_blocked TINYINT(1) NOT NULL DEFAULT 0,
  end_date DATETIME(6) NULL
);
-- Ensure only one active user per id
CREATE UNIQUE INDEX ux_user_active_id
  ON user(id, (CASE WHEN is_active = 1 THEN 1 END));

-- USER_CREDENTIAL
-- Authentication data for technical users.
-- Only one active credential per user. Password stored as hash.
CREATE TABLE user_credential (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id VARCHAR(15) NOT NULL,
  start_date DATETIME(6) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  end_date DATETIME(6) NOT NULL,

  CONSTRAINT fk_credential_user FOREIGN KEY (user_id)
    REFERENCES user(id)
    ON UPDATE CASCADE ON DELETE CASCADE
);
-- Ensure only one active credential per user
CREATE UNIQUE INDEX ux_user_active_credential
  ON user_credential(user_id, (CASE WHEN is_active = 1 THEN 1 END));

-- CATEGORY
-- Product categories for classification and filtering.
CREATE TABLE category (
  slug VARCHAR(100) PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE,
  description TEXT NULL,
  icon VARCHAR(50) NULL,
  display_order INT NOT NULL DEFAULT 999,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  created_by VARCHAR(15) NULL,
  CONSTRAINT fk_category_created_by FOREIGN KEY (created_by)
    REFERENCES user(id)
    ON UPDATE CASCADE ON DELETE SET NULL
);
CREATE INDEX idx_category_active ON category(is_active, display_order);

-- PRODUCT_MASTER
-- Immutable reference entity representing the product code (SKU).
-- Each SKU can have multiple historical versions in product_version.
CREATE TABLE product_master (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  product_code VARCHAR(100) NOT NULL UNIQUE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  created_by VARCHAR(15) NULL, -- FK to user.id (optional)
  CONSTRAINT fk_product_master_created_by FOREIGN KEY (created_by)
    REFERENCES user(id)
    ON UPDATE CASCADE ON DELETE SET NULL
);

-- PRODUCT_VERSION
-- Historical versions of each product.
-- Only one active version per SKU is allowed at any given time.
CREATE TABLE product_version (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  product_master_id BIGINT NOT NULL,
  category_slug VARCHAR(100) NOT NULL,
  name VARCHAR(255) NOT NULL,
  description TEXT NULL,
  price DECIMAL(12,2) NOT NULL,
  created_by VARCHAR(15) NOT NULL,
  start_date DATETIME(6) NOT NULL,
  updated_by VARCHAR(15) NOT NULL,
  last_update DATETIME(6) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  deleted_by VARCHAR(15) NULL,
  end_date DATETIME(6) NULL,

  -- generated field for uniqueness constraint
  is_current TINYINT(1)
    AS (CASE WHEN is_active = 1 AND end_date IS NULL THEN 1 ELSE 0 END) STORED,

  CONSTRAINT fk_product_version_master FOREIGN KEY (product_master_id)
    REFERENCES product_master(id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_product_version_category FOREIGN KEY (category_slug)
    REFERENCES category(slug)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_product_version_created_by FOREIGN KEY (created_by)
    REFERENCES user(id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_product_version_updated_by FOREIGN KEY (updated_by)
    REFERENCES user(id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_product_version_deleted_by FOREIGN KEY (deleted_by)
    REFERENCES user(id)
    ON UPDATE CASCADE ON DELETE SET NULL
);
-- Ensure only one active version per product_master
CREATE UNIQUE INDEX ux_product_version_current
  ON product_version (product_master_id, (CASE WHEN is_current = 1 THEN 1 END));

-- CUSTOMER
-- Final buyers.
-- Soft-delete pattern with is_active + end_date.
CREATE TABLE customer (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  start_date DATETIME(6) NOT NULL,
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  is_blocked TINYINT(1) NOT NULL DEFAULT 0,
  end_date DATETIME(6) NULL
);

-- CUSTOMER_CREDENTIAL
-- Authentication data for customers.
-- Only one active credential per customer. Password stored as hash.
CREATE TABLE customer_credential (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  customer_id BIGINT NOT NULL,
  start_date DATETIME(6) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  end_date DATETIME(6) NOT NULL,

  CONSTRAINT fk_credential_customer FOREIGN KEY (customer_id)
    REFERENCES customer(id)
    ON UPDATE CASCADE ON DELETE CASCADE
);
-- Ensure only one active credential per customer
CREATE UNIQUE INDEX ux_customer_active_credential
  ON customer_credential(customer_id, (CASE WHEN is_active = 1 THEN 1 END));

-- CUSTOMER_ORDER
-- Header of each order (stateful).
-- Stores billing/shipping info and lifecycle timestamps.
CREATE TABLE customer_order (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  customer_id BIGINT NOT NULL,
  start_date DATETIME(6) NOT NULL,
  payment_provider VARCHAR(50) NULL,
  transaction_id VARCHAR(100) NULL,
  payment_status ENUM('COMPLETED', 'FAILED') NULL,
  payment_date DATETIME(6) NULL,
  status ENUM(
    'CART',
    'RESERVED',
    'EXPIRED',
    'NEW',
    'PROCESSING',
    'SHIPPING',
    'SHIPPED',
    'DELIVERED',
    'CANCELLED'
  ) NOT NULL,
  -- Shipping destination (may differ from customer)
  shipping_first_name VARCHAR(100) NULL,
  shipping_last_name VARCHAR(100) NULL,
  address_line VARCHAR(255) NULL,
  city VARCHAR(100) NULL,
  postal_code VARCHAR(10) NULL,
  province VARCHAR(100) NULL,
  user_id VARCHAR(15) NULL, -- FK to user.id (who handled the order)
  last_update DATETIME(6) NOT NULL,

  CONSTRAINT fk_order_customer FOREIGN KEY (customer_id)
    REFERENCES customer(id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ORDER_ITEM
-- Links orders with purchased products, quantities and prices (snapshot at purchase time).
CREATE TABLE order_item (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT NOT NULL,
  product_master_id BIGINT NOT NULL,
  product_version_id BIGINT NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  quantity INT NOT NULL,

  CONSTRAINT fk_order_item_order FOREIGN KEY (order_id)
    REFERENCES customer_order(id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_order_item_product_master FOREIGN KEY (product_master_id)
    REFERENCES product_master(id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_order_item_product_version FOREIGN KEY (product_version_id)
    REFERENCES product_version(id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

-- SHIPMENT
-- Shipment tracking information for orders.
-- Tracks shipping status, carrier, and delivery timeline.
CREATE TABLE shipment (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT NOT NULL,
  carrier VARCHAR(100) NOT NULL,
  tracking_code VARCHAR(200) NOT NULL UNIQUE,
  status ENUM(
    'CREATED',
    'PICKED_UP',
    'IN_TRANSIT',
    'OUT_FOR_DELIVERY',
    'DELIVERED',
    'FAILED'
  ) NOT NULL DEFAULT 'CREATED',
  shipment_date DATETIME(6) NULL,
  estimated_delivery DATETIME(6) NULL,
  delivered_at DATETIME(6) NULL,
  created_by VARCHAR(100) NOT NULL,
  updated_by VARCHAR(100) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  last_update DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

  CONSTRAINT fk_shipment_order FOREIGN KEY (order_id)
    REFERENCES customer_order(id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

-- INVENTORY_QUANTITY
-- Stock quantity per SKU (single warehouse scenario).
-- Tracked both for technical updates and automatic adjustments by orders.
CREATE TABLE inventory_quantity (
  product_master_id BIGINT PRIMARY KEY,
  available_quantity INT NOT NULL,
  reserved_quantity INT NOT NULL DEFAULT 0,
  safety_stock INT NOT NULL DEFAULT 0,
  updated_by_user VARCHAR(15) NULL,
  updated_by_order BIGINT NULL,
  last_update DATETIME(6) NOT NULL,

  CONSTRAINT fk_inventory_product FOREIGN KEY (product_master_id)
    REFERENCES product_master(id)
    ON UPDATE CASCADE ON DELETE RESTRICT,

  CONSTRAINT fk_inventory_updated_by_user FOREIGN KEY (updated_by_user)
    REFERENCES user(id)
    ON UPDATE CASCADE ON DELETE SET NULL,

  CONSTRAINT fk_inventory_updated_by_order FOREIGN KEY (updated_by_order)
    REFERENCES customer_order(id)
    ON UPDATE CASCADE ON DELETE SET NULL
);

-- CUSTOMER_WISHLIST
-- Products saved by customers for later purchase or price tracking.
CREATE TABLE customer_wishlist (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  customer_id BIGINT NOT NULL,
  product_code VARCHAR(100) NOT NULL,
  added_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  
  CONSTRAINT fk_wishlist_customer FOREIGN KEY (customer_id)
    REFERENCES customer(id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_wishlist_product FOREIGN KEY (product_code)
    REFERENCES product_master(product_code)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ux_wishlist_customer_product UNIQUE (customer_id, product_code)
);
CREATE INDEX idx_wishlist_customer ON customer_wishlist(customer_id);
CREATE INDEX idx_wishlist_product ON customer_wishlist(product_code);

-- JWT_BLACKLIST
-- Stores invalidated JWT tokens to prevent reuse after logout.
-- Tokens are identified by JTI (JWT ID) which is a hash of the token.
-- Generic table that can be used for any type of user (technical users, customers, etc.)
CREATE TABLE jwt_blacklist (
  token_jti VARCHAR(255) PRIMARY KEY,
  user_reference VARCHAR(50) NULL, -- Generic reference (user ID, customer ID, etc.)
  user_type VARCHAR(20) NULL, -- Type of user ('user', 'customer', etc.)
  invalidated_at DATETIME(6) NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  reason VARCHAR(255) NULL -- Optional reason for blacklisting
);
