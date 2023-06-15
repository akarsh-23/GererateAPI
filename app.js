const express = require('express');
const faker = require('faker');

const app = express();

// Generate dummy data
function generateData(fields, count) {
  const records = [];

  for (let i = 0; i < count; i++) {
    const record = {};

    fields.forEach((field) => {
      switch (field) {
        case 'firstName':
          record[field] = faker.name.firstName();
          break;
        case 'lastName':
          record[field] = faker.name.lastName();
          break;
        case 'email':
          record[field] = faker.internet.email();
          break;
        default:
          console.log(`Invalid field: ${field}`);
      }
    });

    records.push(record);
  }

  return records;
}


// API route
app.get('/api/dummy-data', (req, res) => {
  const { fields, count } = req.query;

  // Check if fields and count are provided
  if (!fields || !count) {
    return res.status(400).json({ error: 'Fields and count parameters are required.' });
  }

  // Convert fields query parameter to an array
  const fieldList = fields.split(',');

  // Generate dummy data
  const data = generateData(fieldList, parseInt(count));

  res.json(data);
});

// Start the server
const port = 80;
app.listen(port, () => {
  console.log(`Server is running on http://localhost:${port}`);
});

