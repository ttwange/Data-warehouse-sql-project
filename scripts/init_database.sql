-- =============================================================
-- Script  : init_database.sql
-- Project : Data Warehouse (Medallion Architecture)
-- Author  : ttwange
-- Date    : 2026-04-25
-- =============================================================
-- Purpose:
--   This script initialises the data warehouse database and
--   creates the three schema layers that follow the Medallion
--   Architecture pattern (Bronze → Silver → Gold).
--
--   Run this script ONCE when setting up the project on a new
--   environment. It must be executed as a superuser or a role
--   with CREATEDB privileges.
--
-- Execution order:
--   1. Run CREATE DATABASE from outside the target database
--      (connect to postgres default db first)
--   2. Connect to data_warehouse
--   3. Run the CREATE SCHEMA statements
-- =============================================================


-- -------------------------------------------------------------
-- DATABASE
-- Creates the top-level database that houses the entire
-- data warehouse. All Bronze, Silver and Gold objects live
-- inside this database.
-- -------------------------------------------------------------
CREATE DATABASE data_warehouse;


-- -------------------------------------------------------------
-- Connect to the new database before creating schemas
-- In psql run:  \c data_warehouse
-- In DBeaver:   switch the active database to data_warehouse
-- -------------------------------------------------------------


-- -------------------------------------------------------------
-- SCHEMA: bronze
-- Raw ingestion layer. Stores data exactly as it arrives from
-- source systems (CSV files, APIs, operational databases).
-- No transformations are applied here.
-- Data engineers write to this layer; analysts do not query it.
-- -------------------------------------------------------------
CREATE SCHEMA bronze;


-- -------------------------------------------------------------
-- SCHEMA: silver
-- Cleansed and conformed layer. Data from bronze is cleaned,
-- typed, deduplicated and standardised here.
-- This is the trusted, analysis-ready version of the raw data.
-- Data scientists and engineers read from this layer.
-- -------------------------------------------------------------
CREATE SCHEMA silver;


-- -------------------------------------------------------------
-- SCHEMA: gold
-- Business-ready layer. Contains star schema fact and dimension
-- tables optimised for reporting and BI tools.
-- This is the layer analysts, dashboards and executives use.
-- -------------------------------------------------------------
CREATE SCHEMA gold;