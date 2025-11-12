# Use an official lightweight Python image
FROM python:3.12-slim

# Set working directory
WORKDIR /app


# Copy your Python script into the container
COPY . .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose port 5000 for Flask
EXPOSE 5000


# Command to run your script
CMD ["python", "app.py"]
