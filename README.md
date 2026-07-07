# LIVE METRICS FOR AGRICULTURAL BIOPREPARATIONS

## Why?

This project answers the need for measure some physicochemical properties during agricultural biopreparations products. In precision agriculture, biopreparations are used to improve crop yields and quality by adding nutrients, organic matter, or other biotic components to the soil or plant material. This project provides a way to monitor and measure the physicochemical properties of these biopreparations in real-time, allowing farmers to make informed decisions about their biopreparations and crop management. The goal is to provide a technical tool for farmers to improve their recipes.

## The architecture

This project uses Elixir because is oriented for local execution, is very lightweight and easy to run on any platform. The firmware for IoT devices is written in C++ and is prepared for ESP32 platforms. Also, TimescaleDB is used as the database to store the system data because it is a time-series database that is optimized for storing and querying large amounts of time-stamped data, also PostgreSQL provides necessary functions.
