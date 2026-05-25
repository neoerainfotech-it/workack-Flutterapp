# 🔧 Debugging Guide - HTTP 500 Error

## Problem
You're getting HTTP 500 errors on:
- `https://www.workack.com/attendance-app/get_dashboard.php`
- `https://www.workack.com/attendance-app/admin_time_logs.php`

## Causes (Most to Least Likely)
1. **Database tables don't exist** ❌
2. **PHP error handling not showing messages** ❌
3. **Database connection issues** ❌
4. **Missing required columns** ❌
5. **File permissions** ❌

---

## 🚀 Step-by-Step Fix

### Step 1: Run Database Setup
**This is the most likely issue!**

1. Upload `setup_database.php` to your server at:
   ```
   https://www.workack.com/attendance-app/setup_database.php
   ```

2. Access it in your browser - this will:
   - ✅ Check if all required tables exist
   - ✅ Create missing tables automatically
   - ✅ Verify database connectivity
   - ✅ Show sample data statistics

3. **IMPORTANT**: After running it, delete `setup_database.php` for security!

---

### Step 2: Check Test Database Connection
After setup, run the test script:

```
https://www.workack.com/attendance-app/test_db_connection.php
```

This will show:
- ✅ If database connection works
- ✅ If all tables exist
- ✅ If columns are correct
- ✅ If sample data exists

---

### Step 3: Test the API
After setup, test the dashboard API:

```
https://www.workack.com/attendance-app/get_dashboard.php?emp_id=EMP-1001
```

**Expected response:**
```json
{
  "status": "success",
  "data": {
    "employee": {
      "full_name": "testerdemo",
      "job_title": "full stock",
      "department": "developer"
    },
    "today": {
      "date": "2026-05-02",
      "check_in_time": "...",
      "check_out_time": "...",
      "status": "Not Checked In",
      "duration_minutes": 0
    },
    "weekly": { ... },
    "monthly": { ... }
  }
}
```

---

### Step 4: Check Error Logs
New error logs are created at:
```
https://www.workack.com/attendance-app/logs/get_dashboard.log
```

**To view logs**, create a log viewer script or download via FTP.

---

## 📋 Files Changed/Added

### Updated Files
- ✅ `get_dashboard.php` - Better error handling and logging
- ✅ `admin_time_logs.php` - Fixed and tested

### New Files to Upload
1. **`setup_database.php`** - Run once, then delete
2. **`test_db_connection.php`** - Keep for debugging
3. **`logs/` directory** - Auto-created for error logs

---

## 🔍 Common Issues

### Issue: "Employee EMP-1001 not found"
**Fix**: Insert test data using this SQL:
```sql
-- Create test user
INSERT INTO users (username, password, role, status) 
VALUES ('demo', '$2y$12$cK59fSASPaIcwb74c/hFRuCGbB3dwJswvax55Kl/9VLGsehpupfqq', 'employee', 'Active');

-- Get the user_id from above query
SET @user_id = (SELECT id FROM users WHERE username = 'demo' LIMIT 1);

-- Create employee details
INSERT INTO employee_details (user_id, employee_id, full_name, department, job_title, work_email, joining_date)
VALUES (@user_id, 'EMP-1001', 'testerdemo', 'developer', 'full stock', 'tester@workack.com', '2026-05-02');

-- Add sample check-in
INSERT INTO time_logs (user_id, check_in_time, check_out_time)
VALUES (@user_id, NOW(), NULL);
```

### Issue: "time_logs table doesn't have required columns"
The table needs: `id`, `user_id`, `check_in_time`, `check_out_time`

Run setup_database.php to auto-fix.

### Issue: Still getting 500 after setup?
1. Check file permissions (should be 644)
2. Verify `db_connect.php` is in same directory
3. Check PHP version (should be 7.4+)
4. Enable PHP error logging in hosting control panel

---

## ✅ Verification Checklist

- [ ] Ran setup_database.php once
- [ ] All tables created successfully
- [ ] test_db_connection.php shows all tables exist
- [ ] EMP-1001 employee found in database
- [ ] get_dashboard.php returns JSON (not 500 error)
- [ ] admin_time_logs.php loads without error
- [ ] Deleted setup_database.php for security

---

## 📞 Still Having Issues?

1. **Check the log file**: `logs/get_dashboard.log`
2. **Enable PHP debugging** (temporarily):
   - Edit get_dashboard.php
   - Change `ini_set('display_errors', 0);` to `1;`
   - Access the URL and note the error
   - Change back to `0;` when done

3. **Test basic connectivity**:
   - Create a simple `test.php` file with `<?php phpinfo(); ?>`
   - If that works, PHP is running correctly
   - Delete test.php when done
