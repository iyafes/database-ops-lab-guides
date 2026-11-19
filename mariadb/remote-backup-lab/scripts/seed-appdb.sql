-- Generated test data for the lab. No real data. Uses the built-in sequence engine (seq_1_to_N).
CREATE TABLE customers (
  id INT PRIMARY KEY,
  name VARCHAR(60) NOT NULL,
  email VARCHAR(80) NOT NULL,
  created_at DATETIME NOT NULL
) ENGINE=InnoDB;

CREATE TABLE products (
  id INT PRIMARY KEY,
  sku VARCHAR(20) NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  note TEXT
) ENGINE=InnoDB;

CREATE TABLE orders (
  id INT PRIMARY KEY,
  customer_id INT NOT NULL,
  placed_at DATETIME NOT NULL,
  total DECIMAL(12,2) NOT NULL,
  FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB;

CREATE TABLE order_items (
  order_id INT NOT NULL,
  line_no INT NOT NULL,
  product_id INT NOT NULL,
  qty INT NOT NULL,
  PRIMARY KEY (order_id, line_no),
  FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB;

CREATE TABLE audit_events (id BIGINT AUTO_INCREMENT PRIMARY KEY, payload BLOB, created_at DATETIME) ENGINE=InnoDB;

INSERT INTO customers SELECT seq, CONCAT('Customer ', seq), CONCAT('user', seq, '@example.test'),
  NOW() - INTERVAL (seq % 365) DAY FROM seq_1_to_5000;
INSERT INTO products SELECT seq, CONCAT('SKU-', LPAD(seq, 5, '0')), ROUND(1 + (seq % 500) * 1.37, 2),
  CONCAT('Description for product ', seq, ' - ', REPEAT('x', 40)) FROM seq_1_to_500;
INSERT INTO orders SELECT seq, 1 + (seq % 5000), NOW() - INTERVAL (seq % 700) HOUR,
  ROUND(10 + (seq % 900) * 1.1, 2) FROM seq_1_to_20000;
INSERT INTO order_items SELECT o.seq, l.seq, 1 + ((o.seq + l.seq) % 500), 1 + (o.seq % 5)
  FROM seq_1_to_20000 o JOIN seq_1_to_3 l;
INSERT INTO audit_events (payload, created_at) SELECT UNHEX(SHA2(seq, 256)), NOW() FROM seq_1_to_2000;

-- Unicode sample row, to prove charset handling survives the round trip
INSERT INTO customers VALUES (5001, 'Zoë Müller 測試 ✓', 'unicode@example.test', NOW());
