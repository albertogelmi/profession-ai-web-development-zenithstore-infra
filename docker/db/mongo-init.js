// MongoDB Initialization Script
// This script creates the zenithstore database and initializes collections

db = db.getSiblingDB('zenithstore');

// Create collections with validation schemas
db.createCollection('product_reviews', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['customerId', 'productCode', 'orderId', 'rating', 'moderationStatus'],
      properties: {
        customerId: { bsonType: 'int' },
        productCode: { bsonType: 'string' },
        orderId: { bsonType: 'int' },
        rating: { bsonType: 'int', minimum: 1, maximum: 5 },
        moderationStatus: { enum: ['pending', 'approved', 'rejected'] }
      }
    }
  }
});

db.createCollection('product_questions', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['customerId', 'productCode', 'question', 'status'],
      properties: {
        customerId: { bsonType: 'int' },
        productCode: { bsonType: 'string' },
        question: { bsonType: 'string' },
        status: { enum: ['pending', 'answered', 'hidden'] }
      }
    }
  }
});

db.createCollection('activity_logs', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['timestamp', 'actorType', 'actorId', 'action', 'resourceType', 'result'],
      properties: {
        actorType: { enum: ['customer', 'user', 'system', 'webhook'] },
        result: { enum: ['success', 'failure', 'pending'] }
      }
    }
  }
});

db.createCollection('notifications', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['customerId', 'type', 'title', 'message', 'priority', 'isRead', 'isDelivered'],
      properties: {
        customerId: { bsonType: 'int' },
        type: { enum: ['order', 'offer', 'advertising', 'promo_personalized'] },
        title: { bsonType: 'string' },
        message: { bsonType: 'string' },
        icon: { bsonType: 'string' },
        link: { bsonType: 'string' },
        priority: { enum: ['low', 'normal', 'high', 'urgent'] },
        isRead: { bsonType: 'bool' },
        isDelivered: { bsonType: 'bool' },
        createdAt: { bsonType: 'date' },
        readAt: { bsonType: ['date', 'null'] },
        deliveredAt: { bsonType: ['date', 'null'] }
      }
    }
  }
});

// Create indexes
db.product_reviews.createIndex({ productCode: 1, moderationStatus: 1 });
db.product_reviews.createIndex({ customerId: 1, createdAt: -1 });
db.product_reviews.createIndex({ rating: -1, createdAt: -1 });
db.product_reviews.createIndex({ customerId: 1, productCode: 1, orderId: 1 }, { unique: true });
db.product_reviews.createIndex({ title: 'text', comment: 'text' });

db.product_questions.createIndex({ productCode: 1, status: 1, createdAt: -1 });
db.product_questions.createIndex({ customerId: 1, createdAt: -1 });
db.product_questions.createIndex({ status: 1, createdAt: -1 });
db.product_questions.createIndex({ question: 'text', 'answer.text': 'text' });

db.activity_logs.createIndex({ actorId: 1, timestamp: -1 });
db.activity_logs.createIndex({ action: 1, result: 1, timestamp: -1 });
db.activity_logs.createIndex({ resourceType: 1, resourceId: 1, timestamp: -1 });
db.activity_logs.createIndex({ actorType: 1, actorId: 1, timestamp: -1 });

db.notifications.createIndex({ customerId: 1, isRead: 1 });
db.notifications.createIndex({ customerId: 1, createdAt: -1 });
db.notifications.createIndex({ customerId: 1, isDelivered: 1 });

print('MongoDB zenithstore database initialized successfully');
