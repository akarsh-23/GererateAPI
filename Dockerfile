# Use the official Node.js image as the base image
FROM node:14-alpine

# Set the working directory in the container
WORKDIR /app

# Copy the package.json and package-lock.json files to the working directory
COPY package*.json ./

# Install application dependencies
RUN npm install --production

# Copy the application code to the container
COPY . .

# Expose the port that the application listens on
EXPOSE 80

# Start the application
CMD ["node", "app.js"]

