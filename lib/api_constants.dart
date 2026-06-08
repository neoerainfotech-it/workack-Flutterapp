class ApiConstants {
  // =========================================================================
  // 🟢 FIXED: Added trailing slash to prevent cPanel HTTP 301 Redirect Payload Drops
  // =========================================================================
  static const String baseUrl = 'https://www.workack.com/attendance-app/';

  // ==========================================
  // DASHBOARD & ATTENDANCE
  // ==========================================
  // ✅ Dashboard Data
  static const String getDashboard = '${baseUrl}get_dashboard.php';
  
  // ✅ Attendance History
  static const String getHistory = '${baseUrl}get_history.php'; 
  
  // ✅ Save Attendance / Face Scan Sync
  static const String saveAttendance = '${baseUrl}save_attendance.php'; 

  // ==========================================
  // LEAVES
  // ==========================================
  static const String getLeaveHistory = '${baseUrl}get_leave_history.php'; 
  static const String applyLeave = '${baseUrl}apply_leave.php';

  // ==========================================
  // AUTHENTICATION
  // ==========================================
  static const String login = '${baseUrl}login.php';

  // ==========================================
  // PROFILE
  // ==========================================
  static const String getProfile = '${baseUrl}get_profile.php';
  static const String updateProfile = '${baseUrl}update_profile.php';
  static const String updatePassword = '${baseUrl}update_password.php';

  // ==========================================
  // TASKS
  // ==========================================
  static const String getTasks = '${baseUrl}get_tasks.php';
  static const String updateTaskStatus = '${baseUrl}update_task_status.php';
  static const String addTask = '${baseUrl}add_task.php';
  static const String deleteTask = '${baseUrl}delete_task.php';

  // ==========================================
  // ANNOUNCEMENTS
  // ==========================================
  static const String getAnnouncements = '${baseUrl}get_announcements.php';
}