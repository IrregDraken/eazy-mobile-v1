BEGIN;

DO $$
DECLARE
  u1 uuid := '00000000-0000-0000-0000-000000000001';
  u2 uuid := '00000000-0000-0000-0000-000000000002';
  post_id uuid := '00000000-0000-0000-0000-000000000010';
  conversation_id uuid := '00000000-0000-0000-0000-000000000020';
  product_id uuid := '00000000-0000-0000-0000-000000000030';
  cart_id uuid := '00000000-0000-0000-0000-000000000040';
  order_id uuid := '00000000-0000-0000-0000-000000000050';
  wallet_id uuid := '00000000-0000-0000-0000-000000000060';
  transaction_id uuid := '00000000-0000-0000-0000-000000000070';
BEGIN
  INSERT INTO users (id, firebase_uid, email) VALUES (u1, 'test-firebase-1', 'test1@example.test'), (u2, 'test-firebase-2', 'test2@example.test');
  INSERT INTO profiles (user_id, username, display_name) VALUES (u1, 'constraint_user_1', 'Test One'), (u2, 'constraint_user_2', 'Test Two');

  BEGIN
    INSERT INTO profiles (user_id, username, display_name) VALUES (u1, 'constraint_user_2', 'Duplicate Username');
    RAISE EXCEPTION 'username uniqueness constraint did not fire';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  INSERT INTO follows (follower_id, followee_id) VALUES (u1, u2);
  BEGIN
    INSERT INTO follows (follower_id, followee_id) VALUES (u1, u2);
    RAISE EXCEPTION 'follow uniqueness constraint did not fire';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  INSERT INTO posts (id, author_id, content) VALUES (post_id, u1, 'constraint test post');
  INSERT INTO likes (user_id, post_id) VALUES (u2, post_id);
  BEGIN
    INSERT INTO likes (user_id, post_id) VALUES (u2, post_id);
    RAISE EXCEPTION 'like uniqueness constraint did not fire';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  INSERT INTO saves (user_id, post_id) VALUES (u2, post_id);
  BEGIN
    INSERT INTO saves (user_id, post_id) VALUES (u2, post_id);
    RAISE EXCEPTION 'save uniqueness constraint did not fire';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  INSERT INTO conversations (id, kind, created_by) VALUES (conversation_id, 'direct', u1);
  INSERT INTO conversation_members (conversation_id, user_id) VALUES (conversation_id, u1), (conversation_id, u2);
  BEGIN
    INSERT INTO conversation_members (conversation_id, user_id) VALUES (conversation_id, u2);
    RAISE EXCEPTION 'conversation membership uniqueness constraint did not fire';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  INSERT INTO products (id, seller_id, name, price_amount, currency, status) VALUES (product_id, u1, 'Constraint Product', 12.50, 'NGN', 'active');
  INSERT INTO inventory (product_id, available_quantity, reserved_quantity) VALUES (product_id, 5, 0);
  INSERT INTO carts (id, buyer_id) VALUES (cart_id, u2);
  INSERT INTO cart_items (cart_id, product_id, quantity, unit_price_amount, currency) VALUES (cart_id, product_id, 2, 12.50, 'NGN');
  INSERT INTO orders (id, buyer_id, currency, subtotal_amount, total_amount, idempotency_key) VALUES (order_id, u2, 'NGN', 25.00, 25.00, 'constraint-order-1');
  INSERT INTO order_items (order_id, product_id, seller_id, quantity, unit_price_amount, line_total_amount, currency) VALUES (order_id, product_id, u1, 2, 12.50, 25.00, 'NGN');

  INSERT INTO wallets (id, user_id, currency) VALUES (wallet_id, u2, 'NGN');
  INSERT INTO transactions (id, user_id, wallet_id, type, amount, currency, reference, idempotency_key) VALUES (transaction_id, u2, wallet_id, 'purchase', 25.00, 'NGN', 'constraint-tx-1', 'constraint-tx-idempotency-1');
  BEGIN
    INSERT INTO transactions (user_id, wallet_id, type, amount, currency, reference, idempotency_key) VALUES (u2, wallet_id, 'purchase', 25.00, 'NGN', 'constraint-tx-2', 'constraint-tx-idempotency-1');
    RAISE EXCEPTION 'transaction idempotency constraint did not fire';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  RAISE NOTICE 'Eazy V2 database constraint tests passed';
END;
$$;

ROLLBACK;
