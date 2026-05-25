import 'package:http/http.dart' as http; 
import 'api_constants.dart';             
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'constants.dart';
import 'profile_screen.dart';
import 'history_screen.dart';
import 'apply_leave_screen.dart';
import 'tasks_screen.dart';
import 'announcements_screen.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

enum WorkState { initial, checkedIn, onBreak, checkedOut }

// =========================================================================
// MAIN LAYOUT — App Navigation & Scaffold
// =========================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Start on the Dashboard (Index 0)
  int _bottomNavIndex = 0;

  final List<Widget> _screens = [
    const AttendanceDashboard(), // Index 0 (Home/Center)
    const ApplyLeaveScreen(),    // Index 1 (First Icon - Left)
    const TasksScreen(),         // Index 2 (Second Icon - Left)
    const HistoryScreen(),       // Index 3 (Third Icon - Right)
    const ProfileScreen(),       // Index 4 (Fourth Icon - Right)
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kMilkWhite,
      body: IndexedStack(index: _bottomNavIndex, children: _screens),
      
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _bottomNavIndex = 0),
        backgroundColor: kPrimaryGreen,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.home_filled, color: Colors.white, size: 28),
      ),
      
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: kIsWeb ? null : const CircularNotchedRectangle(),
        notchMargin: 8.0,
        elevation: 10,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavIcon(Icons.edit_calendar_rounded, 1), 
              _buildNavIcon(Icons.task_alt_rounded, 2),
              
              const SizedBox(width: 40), // Gap for Home FAB
              
              _buildNavIcon(Icons.calendar_today_rounded, 3), 
              _buildNavIcon(Icons.person_rounded, 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, int index) {
    bool isActive = _bottomNavIndex == index;
    return IconButton(
      icon: Icon(icon, color: isActive ? kPrimaryGreen : kTextMuted, size: 28),
      onPressed: () => setState(() => _bottomNavIndex = index),
    );
  }
}

// =========================================================================
// ATTENDANCE DASHBOARD — The Core Logic & UI
// =========================================================================
class AttendanceDashboard extends StatefulWidget {
  const AttendanceDashboard({super.key});

  @override
  State<AttendanceDashboard> createState() => _AttendanceDashboardState();
}

class _AttendanceDashboardState extends State<AttendanceDashboard> with WidgetsBindingObserver {
  
  int _selectedDateIndex = 6; 
  DateTime _selectedDate = DateTime.now(); 
  List<DateTime> _recentDays = [];
  List<Map<String, dynamic>> _attendanceLogs = []; 

  final ScrollController _dateScrollController = ScrollController();

  final List<String> _companyHolidays = [
    "2026-01-26", // Republic Day
    "2026-05-01", // May Day
    "2026-08-15", // Independence Day
    "2026-10-02", // Gandhi Jayanti
  ];

  Map<String, dynamic> _attendanceDatabase = {};
  double _swipePosition = 0.0;
  bool _isLoading = true;
  bool _isActionLocked = false; 
  bool _isSwiping = false; 
  Timer? _uiTickTimer; 
  double? _officeLat;
  double? _officeLon;

  String _employeeName = "Loading...";
  String _jobTitle = "Loading...";
  Map<String, dynamic> _todayData = {};

  Uint8List? _customAvatarBytes;
  String? _customAvatarPath;

  int _unreadAnnouncements = 0;
  int _totalAnnouncements = 0; 

  bool _isAbsent(DateTime date) {
    if (date.isAfter(DateTime.now()) || _getDateKey(date) == _todayKey) return false;
    
    if (date.weekday == DateTime.sunday || date.weekday == DateTime.saturday) return false;
    if (_companyHolidays.contains(_getDateKey(date))) return false;

    String key = _getDateKey(date);
    
    if (!_attendanceDatabase.containsKey(key)) return false; 
    
    return _attendanceDatabase[key]['checkInTime'] == null;
  }

  Color _getDateCardColor(DateTime date, bool isSelected) {
    if (isSelected) return kPrimaryGreen; 

    if (date.weekday == DateTime.sunday) return Colors.red.shade50; 
    
    if (date.weekday == DateTime.saturday || _companyHolidays.contains(_getDateKey(date))) {
      return Colors.blueGrey.shade50; 
    }

    return Colors.white; 
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generateDates();
    _loadSavedState();
    _fetchDashboardData();
    fetchAttendanceHistory(); 

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_dateScrollController.hasClients) {
          _dateScrollController.animateTo(
            _dateScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutQuart, 
          );
        }
      });
    });
    
    _uiTickTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) return;
      _handleMidnightRollover();
      _fetchDashboardData(); 
      setState(() {}); 
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiTickTimer?.cancel();
    _dateScrollController.dispose();
    super.dispose();
  }

  Future<void> fetchAttendanceHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? empId = prefs.getString('emp_id');
      if (empId == null) return;

      final String formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final response = await http.post(
        Uri.parse(ApiConstants.getHistory),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          'emp_id': empId,
          'date': formattedDate, 
        },
      );

      if (response.statusCode == 200) {
        String cleanBody = response.body.trim().replaceFirst(RegExp(r'^\ufeff'), '');
        debugPrint("RAW HISTORY RESPONSE: $cleanBody"); 

        final data = json.decode(cleanBody);
        
        if (data['status'] == 'success') {
          setState(() {
            _attendanceLogs = (data['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(); 
            
            String key = _getDateKey(_selectedDate);
            if (!_attendanceDatabase.containsKey(key)) {
              _attendanceDatabase[key] = <String, dynamic>{};
            }
            
            if (_attendanceLogs.isNotEmpty) {
              _attendanceLogs.sort((a, b) => (a['check_in_time'] ?? '').compareTo(b['check_in_time'] ?? ''));
              _attendanceDatabase[key]['checkInTime'] = _attendanceLogs.first['check_in_time'];
            } else if (_selectedDate.isBefore(DateTime.now()) && _getDateKey(_selectedDate) != _todayKey) {
              _attendanceDatabase[key]['checkInTime'] = null; 
            }
            _saveState(); 
          });
        } else {
           _showInlineStatus("Server says: ${data['message']}");
        }
      }
    } catch (e) {
      debugPrint("History Fetch Crash: $e");
      _showInlineStatus("App Crash: $e"); 
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleMidnightRollover();
      setState(() {}); 
    }
  }

  String _getDateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
  
  String get _todayKey => _getDateKey(DateTime.now());
  String get _viewingKey => _getDateKey(_recentDays[_selectedDateIndex]);

  void _handleMidnightRollover() {
    if (_attendanceDatabase.isEmpty) return;
    
    DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    String yKey = _getDateKey(yesterday);
    
    if (_attendanceDatabase.containsKey(yKey)) {
      var yData = _attendanceDatabase[yKey] as Map<String, dynamic>;
      int stateIndex = yData['workState'] as int? ?? 0;
      
      if (stateIndex == WorkState.checkedIn.index || stateIndex == WorkState.onBreak.index) {
        DateTime forcedCheckout = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59);
        yData['workState'] = WorkState.checkedOut.index;
        yData['checkOutTime'] = forcedCheckout.toIso8601String();
        if (stateIndex == WorkState.onBreak.index && yData['breakStartTime'] != null) {
          DateTime bs = DateTime.parse(yData['breakStartTime'] as String);
          yData['breakMinutes'] = (yData['breakMinutes'] as int? ?? 0) + forcedCheckout.difference(bs).inMinutes;
          yData['breakStartTime'] = null;
        }
        _attendanceDatabase[yKey] = yData;
        _saveState();
      }
    }
  }

  Future<void> _loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    String? dbJson = prefs.getString('attendance_db');
    
    if (dbJson != null) {
      setState(() {
        _attendanceDatabase = Map<String, dynamic>.from(jsonDecode(dbJson) as Map);
      });
    }
    
    if (!_attendanceDatabase.containsKey(_todayKey)) {
      _attendanceDatabase[_todayKey] = <String, dynamic>{
        'workState': WorkState.initial.index,
        'breakMinutes': 0,
      };
    }
    
    _handleMidnightRollover();
    setState(() => _isLoading = false);
  }

  Future<void> _fetchDashboardData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? empId = prefs.getString('emp_id');
      final String? companyId = prefs.getString('company_id');

      if (kIsWeb) {
        final savedWeb = prefs.getString('profile_image_web');
        if (savedWeb != null) setState(() => _customAvatarBytes = base64Decode(savedWeb));
      } else {
        setState(() => _customAvatarPath = prefs.getString('profile_image_mobile'));
      }
      
      debugPrint("📱 Checking Emp ID: $empId"); 

      if (empId == null) return;

      final response = await http.post(
        Uri.parse(ApiConstants.getDashboard),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          'emp_id': empId,
          'company_id': companyId ?? '0',
        },
      );
      debugPrint("🌐 Server Response: ${response.body}"); 

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['status'] == 'success') {
          
          final dashboardData = responseData['data'];
          
          if (dashboardData == null || dashboardData is! Map || dashboardData.isEmpty) {
            debugPrint("⚠️ WARNING: Backend returned empty or invalid data: $dashboardData");
            return;
          }
          
          final employeeInfo = dashboardData['employee'];
          
          if (employeeInfo == null || employeeInfo is! Map) {
            debugPrint("⚠️ ERROR: Backend returned invalid employee data");
            return;
          }
          
          setState(() {
            _employeeName = employeeInfo['full_name']?.toString() ?? 'Guest User';
            _jobTitle = employeeInfo['job_title']?.toString() ?? 'Employee';

            _officeLat = employeeInfo['office_lat'] != null ? double.tryParse(employeeInfo['office_lat'].toString()) : null;
            _officeLon = employeeInfo['office_lon'] != null ? double.tryParse(employeeInfo['office_lon'].toString()) : null;

            _todayData = (dashboardData['today'] as Map?)?.cast<String, dynamic>() ?? {};

            _totalAnnouncements = dashboardData['total_announcements'] ?? 1; 
            
            int lastSeen = prefs.getInt('seen_announcements') ?? 0;
            
            _unreadAnnouncements = _totalAnnouncements > lastSeen 
                ? _totalAnnouncements - lastSeen 
                : 0;

            if (_todayData['status'] == 'Checked In') {
              _attendanceDatabase[_todayKey]?['workState'] = WorkState.checkedIn.index;
            } else if (_todayData['status'] == 'Checked Out') {
              _attendanceDatabase[_todayKey]?['workState'] = WorkState.checkedOut.index;
            } else {
              _attendanceDatabase[_todayKey]?['workState'] = WorkState.initial.index;
            }
            
            _attendanceDatabase[_todayKey]?['checkInTime'] = _todayData['check_in_time'];
            _attendanceDatabase[_todayKey]?['checkOutTime'] = _todayData['check_out_time'];
            _attendanceDatabase[_todayKey]?['durationMinutes'] = _todayData['duration_minutes'];
          });
          
          _saveState();
        }
      }
    } on TimeoutException {
      debugPrint('Dashboard fetch timeout');
    } catch (e) {
      debugPrint('Dashboard fetch error: $e');
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('attendance_db', jsonEncode(_attendanceDatabase));
  }

  Map<String, dynamic> _getViewedData() {
    if (_attendanceDatabase.containsKey(_viewingKey)) {
      return Map<String, dynamic>.from(_attendanceDatabase[_viewingKey] as Map);
    }
    return <String, dynamic>{
      'workState': WorkState.initial.index,
      'breakMinutes': 0,
    };
  }

  void _updateTodayData(String key, dynamic value) {
    if (!_attendanceDatabase.containsKey(_todayKey)) {
      _attendanceDatabase[_todayKey] = <String, dynamic>{};
    }
    _attendanceDatabase[_todayKey][key] = value;
    _saveState();
  }

  void _generateDates() {
    DateTime today = DateTime.now();
    _recentDays = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  }

  Future<void> _selectCustomDate() async {
    DateTime initial = _recentDays[_selectedDateIndex];
    
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1, 1), 
      lastDate: DateTime.now(),        
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: kPrimaryGreen, 
              onPrimary: Colors.white,
              onSurface: kTextDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _recentDays = List.generate(7, (i) => picked.subtract(Duration(days: 6 - i)));
        _selectedDateIndex = 6; 
      });
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return "--:--";
    DateTime time = DateTime.parse(timeStr);
    int h = time.hour;
    int m = time.minute;
    String ampm = h >= 12 ? "pm" : "am";
    h = h % 12;
    if (h == 0) h = 12;
    return "$h:${m.toString().padLeft(2, '0')} $ampm";
  }

  String _calculateTotalHours(Map<String, dynamic> data) {
    int totalMinutes = 0;
    int breakMins = data['breakMinutes'] as int? ?? 0;

    if (_attendanceLogs.isNotEmpty) {
      for (var log in _attendanceLogs) {
        if (log['check_in_time'] != null && log['check_out_time'] != null) {
          DateTime inTime = DateTime.parse(log['check_in_time']);
          DateTime outTime = DateTime.parse(log['check_out_time']);
          totalMinutes += outTime.difference(inTime).inMinutes;
        }
      }
    } 
    else {
      if (data['checkInTime'] == null) return "--";
      DateTime checkIn = DateTime.parse(data['checkInTime'] as String);
      DateTime endTime = data['checkOutTime'] != null ? DateTime.parse(data['checkOutTime'] as String) : DateTime.now();
      
      if (data['checkOutTime'] == null && _viewingKey != _todayKey) {
        endTime = DateTime(checkIn.year, checkIn.month, checkIn.day, 23, 59);
      }
      totalMinutes = endTime.difference(checkIn).inMinutes;

      if (data['workState'] == WorkState.onBreak.index && data['breakStartTime'] != null) {
        breakMins += DateTime.now().difference(DateTime.parse(data['breakStartTime'] as String)).inMinutes;
      }
    }

    int netWorkingMinutes = totalMinutes - breakMins;
    if (netWorkingMinutes < 0) netWorkingMinutes = 0;

    int hours = netWorkingMinutes ~/ 60;
    int mins = netWorkingMinutes % 60;
    return "${hours}h ${mins}m";
  }

  int _calculateTotalBreak(Map<String, dynamic> data) {
    int breakMins = data['breakMinutes'] as int? ?? 0;
    if (data['workState'] == WorkState.onBreak.index && data['breakStartTime'] != null && _viewingKey == _todayKey) {
      breakMins += DateTime.now().difference(DateTime.parse(data['breakStartTime'] as String)).inMinutes;
    }
    return breakMins;
  }

  Future<void> _verifyLocationAndScan() async {
    setState(() => _isActionLocked = true);
    _showInlineStatus("Getting location...");

    Position? currentPosition;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showInlineStatus("Please turn on your GPS.");
        setState(() { _swipePosition = 0.0; _isActionLocked = false; });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showInlineStatus("Location permissions denied.");
          setState(() { _swipePosition = 0.0; _isActionLocked = false; });
          return;
        }
      }

      currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      if (_officeLat != null && _officeLon != null) {
        double distanceInMeters = Geolocator.distanceBetween(
          currentPosition.latitude, currentPosition.longitude, _officeLat!, _officeLon!
        );

        if (distanceInMeters > 200) { 
          int distanceAway = distanceInMeters.round();
          _showInlineStatus("You are $distanceAway meters away from the office!");
          setState(() { _swipePosition = 0.0; _isActionLocked = false; });
          return;
        }
      }

      setState(() => _isActionLocked = false); 
      _startFaceScan(position: currentPosition); 

    } catch (e) {
      _showInlineStatus("Failed to get location.");
      setState(() { _swipePosition = 0.0; _isActionLocked = false; });
    }
  }

  void _startFaceScan({Position? position}) {
    if (_isActionLocked || !mounted) return;
    setState(() => _isActionLocked = true);

    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, 
      builder: (context) => const FaceScanModal(), 
    ).then((success) {
      if (!mounted) return;
      if (success == true) {
        final nowIso = DateTime.now().toIso8601String(); 
        
        setState(() {
          _updateTodayData('workState', WorkState.checkedIn.index);
          _updateTodayData('checkInTime', nowIso);
          _swipePosition = 0.0; 
        });
        
        _showInlineStatus("Identity Verified. Checked In!");
        _syncAttendanceWithServer('check_in', nowIso, lat: position?.latitude, lon: position?.longitude);
      } else {
        setState(() => _swipePosition = 0.0);
      }
      setState(() => _isActionLocked = false); 
    });
  }

  void _handleBreakToggle() {
    var data = _getViewedData();
    int currentState = data['workState'] as int? ?? 0;
    
    setState(() {
      if (currentState == WorkState.checkedIn.index) {
        _updateTodayData('workState', WorkState.onBreak.index);
        _updateTodayData('breakStartTime', DateTime.now().toIso8601String());
      } else if (currentState == WorkState.onBreak.index) {
        _updateTodayData('workState', WorkState.checkedIn.index);
        if (data['breakStartTime'] != null) {
          int addedMins = DateTime.now().difference(DateTime.parse(data['breakStartTime'] as String)).inMinutes;
          _updateTodayData('breakMinutes', (data['breakMinutes'] as int? ?? 0) + addedMins);
          _updateTodayData('breakStartTime', null); 
        }
      }
    });
  }

  void _promptCheckOut() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("End Shift?", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to clock out? You cannot undo this action."),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: kTextMuted))),
          _buildCheckOutButton(context),
        ],
      ),
    );
  }

  Widget _buildCheckOutButton(BuildContext dialogContext) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
      onPressed: () async {
        Navigator.pop(dialogContext);
        if (!mounted) return;

        setState(() => _isActionLocked = true);
        _showInlineStatus("Getting final location...");

        Position? currentPosition;
        try {
          currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        } catch (e) {
          debugPrint("Failed to get location on checkout");
        }
        
        final nowIso = DateTime.now().toIso8601String();
        final totalBreak = _calculateTotalBreak(_getViewedData()); 
        
        setState(() {
          _updateTodayData('workState', WorkState.checkedOut.index);
          _updateTodayData('checkOutTime', nowIso);
          _isActionLocked = false;
        });
        
        _showInlineStatus("Checked Out for the day");
        _syncAttendanceWithServer('check_out', nowIso, breakMins: totalBreak, lat: currentPosition?.latitude, lon: currentPosition?.longitude);
      }, 
      child: const Text("Check Out", style: TextStyle(color: Colors.white)),
    );
  }

  void _showInlineStatus(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        backgroundColor: kTextDark.withValues(alpha: 0.85),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 50, right: 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<Widget> _buildActivityLog(Map<String, dynamic> data) {
    List<Widget> logs = [];

    if (_attendanceLogs.isNotEmpty) {
      for (var log in _attendanceLogs) {
        logs.add(_buildTimelineItem(
            "Checked In",
            _formatTime(log['check_in_time']?.toString()),
            Icons.login_rounded,
            kPrimaryGreen));

        int breaks = int.tryParse(log['break_minutes']?.toString() ?? '0') ?? 0;
        if (breaks > 0) {
          logs.add(_buildTimelineItem(
              "Took a Break",
              "$breaks min total",
              Icons.coffee_rounded,
              Colors.orange));
        }

        if (log['check_out_time'] != null) {
          logs.add(_buildTimelineItem(
              "Checked Out",
              _formatTime(log['check_out_time']?.toString()),
              Icons.logout_rounded,
              Colors.redAccent));
        }
      }
    } 
    else if (data['checkInTime'] != null) {
      logs.add(_buildTimelineItem(
          "Checked In", 
          _formatTime(data['checkInTime'] as String?), 
          Icons.login_rounded, kPrimaryGreen));

      if (data['breakStartTime'] != null || (data['breakMinutes'] != null && (data['breakMinutes'] as int) > 0)) {
        logs.add(_buildTimelineItem(
            "Took a Break", 
            "${_calculateTotalBreak(data)} min total", 
            Icons.coffee_rounded, Colors.orange));
      }

      if (data['checkOutTime'] != null) {
        logs.add(_buildTimelineItem(
            "Checked Out", 
            _formatTime(data['checkOutTime'] as String?), 
            Icons.logout_rounded, Colors.redAccent));
      }
    }

    if (logs.isEmpty) {
      logs.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
            child: Text("No activity recorded for this date.",
                style: GoogleFonts.inter(
                    color: kTextMuted, fontStyle: FontStyle.italic))),
      ));
    }

    return logs;
  }

  Widget _buildTimelineItem(String title, String time, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kTextDark))),
          Text(time, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: kTextDark)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kPrimaryGreen));
    }

    bool isViewingToday = _viewingKey == _todayKey;
    var currentData = _getViewedData();

    if (_attendanceLogs.isNotEmpty) {
      _attendanceLogs.sort((a, b) => (a['check_in_time'] ?? '').compareTo(b['check_in_time'] ?? ''));

      currentData['checkInTime'] = _attendanceLogs.first['check_in_time'];
      currentData['checkOutTime'] = _attendanceLogs.last['check_out_time'];
      
      int totalBreaks = 0;
      for (var log in _attendanceLogs) {
        totalBreaks += int.tryParse(log['break_minutes']?.toString() ?? '0') ?? 0;
      }
      currentData['breakMinutes'] = totalBreaks;
      
    } else if (!isViewingToday) {
      currentData['checkInTime'] = null;
      currentData['checkOutTime'] = null;
      currentData['breakMinutes'] = 0;
    }

    WorkState displayedState = WorkState.values[currentData['workState'] as int? ?? 0];
    
    final monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
    String currentMonth = "${monthNames[_recentDays[_selectedDateIndex].month - 1]} ${_recentDays[_selectedDateIndex].year}";

    return SafeArea(
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 16.0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    
                   // HEADER 
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ProfileScreen()),
                            );
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle, 
                                  border: Border.all(color: kPrimaryGreen, width: 2), 
                                  color: kMilkWhite
                                ),
                                child: ClipOval(
                                  child: (kIsWeb && _customAvatarBytes != null)
                                      ? Image.memory(_customAvatarBytes!, fit: BoxFit.cover, width: 48, height: 48)
                                      : (!kIsWeb && _customAvatarPath != null)
                                          ? Image.network(
                                              _customAvatarPath!, 
                                              fit: BoxFit.cover, width: 48, height: 48, 
                                              errorBuilder: (c, e, s) => Image.network('https://ui-avatars.com/api/?name=${Uri.encodeComponent(_employeeName)}&background=006B3C&color=fff&size=128&bold=true', fit: BoxFit.cover, width: 48, height: 48)
                                            )
                                          : Image.network('https://ui-avatars.com/api/?name=${Uri.encodeComponent(_employeeName)}&background=006B3C&color=fff&size=128&bold=true', fit: BoxFit.cover, width: 48, height: 48),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_employeeName, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: kTextDark)),
                                  Text(_jobTitle, style: GoogleFonts.inter(fontSize: 13, color: kTextMuted, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        Row(
                          children: [
                            IconButton(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const AnnouncementsScreen()),
                                );
                                
                                if (mounted) {
                                  setState(() => _unreadAnnouncements = 0); 
                                  
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setInt('seen_announcements', _totalAnnouncements);
                                }
                              },
                              icon: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.notifications_none_rounded, color: kTextDark, size: 28),
                                  
                                  if (_unreadAnnouncements > 0)
                                    Positioned(
                                      right: -2,
                                      top: -4,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent,
                                          borderRadius: BorderRadius.circular(10), 
                                          border: Border.all(color: Colors.white, width: 1.5),
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 18,
                                          minHeight: 18,
                                        ),
                                        child: Text(
                                          _unreadAnnouncements > 9 ? '9+' : '$_unreadAnnouncements',
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            height: 1.1, 
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 32),

                   // DATE SELECTOR WITH MONTH CONTEXT
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(currentMonth, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: kTextDark)),
                        IconButton(
                          onPressed: _selectCustomDate,
                          icon: const Icon(Icons.calendar_month_rounded, color: kPrimaryGreen, size: 24),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(), 
                          splashRadius: 24,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        controller: _dateScrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: _recentDays.length,
                        itemBuilder: (context, index) {
                          DateTime date = _recentDays[index];
                          bool isSelected = _selectedDateIndex == index;
                          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedDateIndex = index;
                                _selectedDate = _recentDays[index]; 
                                _attendanceLogs = []; 
                              });
                              fetchAttendanceHistory(); 
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.only(right: 12),
                              width: 65,
                              decoration: BoxDecoration(
                                color: _getDateCardColor(date, isSelected), 
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _isAbsent(date) ? Colors.redAccent.withValues(alpha: 0.6) 
                                       : (isSelected ? Colors.transparent : Colors.black.withValues(alpha: 0.05)),
                                  width: _isAbsent(date) ? 1.5 : 1.0,
                                ), 
                                boxShadow: isSelected ? [BoxShadow(color: kPrimaryGreen.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))] : [], 
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    date.day.toString().padLeft(2, '0'), 
                                    style: GoogleFonts.inter(
                                      fontSize: 18, 
                                      fontWeight: FontWeight.bold, 
                                      color: isSelected ? Colors.white : (date.weekday == DateTime.sunday ? Colors.redAccent : kTextDark)
                                    )
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    days[date.weekday - 1], 
                                    style: GoogleFonts.inter(
                                      fontSize: 12, 
                                      color: isSelected ? Colors.white70 : (date.weekday == DateTime.sunday ? Colors.redAccent.withValues(alpha: 0.6) : kTextMuted)
                                    )
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 32),

                    // DYNAMIC ATTENDANCE GRID
                    Text("Dashboard", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: kTextDark)),
                    const SizedBox(height: 16),
                    GridView(
                      shrinkWrap: true, 
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, mainAxisExtent: 140, 
                      ),
                      children: [
                        _buildGridCard("Check In", _formatTime(currentData['checkInTime'] as String?), currentData['checkInTime'] == null ? "Pending" : "Verified Identity", Icons.login_rounded),
                        
                        _buildGridCard("Check Out", _formatTime(currentData['checkOutTime'] as String?), currentData['checkOutTime'] == null ? (displayedState == WorkState.initial && currentData['checkInTime'] == null ? "Pending" : "Active Shift") : "Shift Ended", Icons.logout_rounded),
                        
                        _buildGridCard("Break Time", currentData['checkInTime'] == null ? "--:--" : "${_calculateTotalBreak(currentData)} min", "Total taken", Icons.coffee_rounded),
                        
                        _buildGridCard("Total Hours", _calculateTotalHours(currentData), "Active Work Time", Icons.access_time_rounded),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ACTIVITY TIMELINE
                    Text("Your Activity", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: kTextDark)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.black.withValues(alpha: 0.03))),
                      child: Column(
                        children: _buildActivityLog(currentData),
                      ),
                    ),
                    
                    const SizedBox(height: 140), 
                  ]),
                ),
              ),
            ],
          ),
          
         // Glassmorphic Panel over the Stack
          if (isViewingToday && displayedState != WorkState.checkedOut)
            Positioned(
              bottom: 35, 
              left: 20,   
              right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32), 
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12), 
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))
                      ]
                    ),
                    child: _buildActionPanel(displayedState),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionPanel(WorkState currentState) {
    if (currentState == WorkState.initial) {
      return LayoutBuilder(
        key: const ValueKey('swipe'),
        builder: (context, constraints) {
          double maxWidth = constraints.maxWidth;
          double buttonWidth = 60.0;
          return Container(
            height: 65,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPrimaryGreen, kSecondaryGreen]),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: kPrimaryGreen.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5))],
            ),
            child: Stack(
              children: [
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.face_retouching_natural_rounded, color: Colors.white70, size: 20),
                      const SizedBox(width: 8),
                      Text("Swipe to Face Scan", style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: _isSwiping ? Duration.zero : const Duration(milliseconds: 400),
                  curve: Curves.easeOutQuart,
                  left: _swipePosition, top: 4, bottom: 4,
                  child: GestureDetector(
                    onHorizontalDragStart: (_) {
                      if (_isActionLocked) return;
                      setState(() => _isSwiping = true);
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_isActionLocked) return;
                      setState(() {
                        _swipePosition = (_swipePosition + details.delta.dx).clamp(0.0, maxWidth - buttonWidth - 8);
                      });
                    },
                    onHorizontalDragEnd: (details) {
                      setState(() => _isSwiping = false);
                      final velocity = details.primaryVelocity ?? 0;
                      if (_swipePosition > maxWidth * 0.7 || velocity > 1000) {
                        setState(() => _swipePosition = maxWidth - buttonWidth - 8);
                        _verifyLocationAndScan(); 
                      } else {
                        setState(() => _swipePosition = 0.0); 
                      }
                    },
                    child: Container(
                      width: buttonWidth, margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                      child: const Icon(Icons.arrow_forward_rounded, color: kPrimaryGreen),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      );
    } else {
      bool isOnBreak = currentState == WorkState.onBreak;
      return Row(
        key: const ValueKey('actions'),
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _handleBreakToggle,
              icon: Icon(isOnBreak ? Icons.timer_rounded : Icons.coffee_rounded, color: isOnBreak ? Colors.blue : Colors.orange),
              label: Text(isOnBreak ? "End Break" : "Take Break", style: const TextStyle(color: kTextDark)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: Colors.black.withValues(alpha: 0.1)), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: isOnBreak ? null : _promptCheckOut, 
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
              label: const Text("Check Out", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildGridCard(String title, String mainValue, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)), 
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 2), spreadRadius: -5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kPrimaryGreen.withValues(alpha: 0.1), 
                  shape: BoxShape.circle
                ), 
                child: Icon(icon, color: kPrimaryGreen, size: 16),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title, 
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTextDark.withValues(alpha: 0.8)), 
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis
                )
              ), 
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown, 
            alignment: Alignment.centerLeft, 
            child: Text(mainValue, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: kTextDark))
          ),
          const SizedBox(height: 4),
          Text(
            subtitle, 
            style: GoogleFonts.inter(fontSize: 11, color: kTextMuted, fontWeight: FontWeight.w500), 
            maxLines: 1, 
            overflow: TextOverflow.ellipsis
          ),
        ],
      ),
    );
  }

  Future<void> _syncAttendanceWithServer(String action, String isoTime, {int breakMins = 0, double? lat, double? lon}) async {
    final logger = Logger(printer: PrettyPrinter(methodCount: 0, errorMethodCount: 5, lineLength: 80, colors: true, printEmojis: true));

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? empId = prefs.getString('emp_id');
      final String? companyId = prefs.getString('company_id'); 

      if (empId == null || empId.isEmpty) {
        logger.e("🛑 SYNC FAILED: emp_id is missing from SharedPreferences!");
        return; 
      }

      logger.i("🔄 Attempting to sync attendance: $action at $isoTime for Employee: $empId");

      Map<String, String> requestBody = {
        'emp_id': empId,
        'company_id': companyId ?? '0',
        'action': action,
        'time': isoTime,
        'break_minutes': breakMins.toString(), 
      };

      if (lat != null && lon != null) {
        requestBody['lat'] = lat.toString();
        requestBody['lon'] = lon.toString();
      }

      final response = await http.post(
          Uri.parse('https://www.workack.com/attendance-app/save_attendance.php'),
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: requestBody,
        ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        logger.d("✅ SERVER RESPONSE: ${response.body}");
      } else {
        logger.e("🛑 SERVER HTTP ERROR: ${response.statusCode}");
      }

    } catch (e) {
      logger.e("🛑 NETWORK ERROR during sync: $e");
    }
  }
}

// =========================================================================
// FACE SCAN MODAL (WITH DEV MODE ENABLED FOR TESTING)
// =========================================================================
class FaceScanModal extends StatefulWidget {
  const FaceScanModal({super.key});
  @override
  State<FaceScanModal> createState() => _FaceScanModalState();
}

class _FaceScanModalState extends State<FaceScanModal> with TickerProviderStateMixin {
  
  final bool isDevMode = kIsWeb; 

  int _scanStatus = 0; 
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isFaceDetected = false;
  bool _cameraInitialized = false;
  int _detectionAttempts = 0;
  late AnimationController _checkAnimController;
  late Animation<double> _checkScaleAnimation;

  @override
  void initState() {
    super.initState();
    _checkAnimController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _checkScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkAnimController, curve: Curves.elasticOut),
    );
    
    if (isDevMode) {
      _simulateDevModeScan();
    } else {
      _initializeRealCamera();
    }
  }

  Future<void> _simulateDevModeScan() async {
    setState(() => _scanStatus = 0);
    await Future.delayed(const Duration(seconds: 2)); 
    if (mounted) {
      _completeFaceScan(true);
    }
  }

  Future<void> _initializeRealCamera() async {
    if (kIsWeb) {
      _simulateDevModeScan();
      return;
    }

    try {
      final Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.locationWhenInUse,
      ].request();
      
      if (!mounted) return;
      
      if (statuses[Permission.camera]!.isDenied || statuses[Permission.locationWhenInUse]!.isDenied) {
        setState(() => _scanStatus = 2);
        _showErrorSnackBar("Camera and Location permissions are required to check in.");
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _scanStatus = 2);
        _showErrorSnackBar("No camera available");
        return;
      }

      _cameraController = CameraController(
        cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front, orElse: () => cameras[0]),
        ResolutionPreset.medium,
        enableAudio: false, 
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS 
            ? ImageFormatGroup.bgra8888 
            : ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(enableLandmarks: false, enableContours: false, enableClassification: false, enableTracking: false),
      );

      if (!mounted) return;
      setState(() {
        _scanStatus = 0;
        _cameraInitialized = true;
      });
      _startFaceDetection();
    } catch (e) {
      if (mounted) {
        setState(() => _scanStatus = 2);
        _showErrorSnackBar("Hardware error: ${e.toString().split('\n').first}");
      }
    }
  }

  void _startFaceDetection() {
    int frameCount = 0;
    _cameraController?.startImageStream((CameraImage image) async {
      if (_isFaceDetected || !mounted) return;
      frameCount++;
      _detectionAttempts++;
      
      if (frameCount % 10 != 0) return;
      
      try {
        final sensorOrientation = _cameraController!.description.sensorOrientation;
        final InputImageRotation rotation = InputImageRotationValue.fromRawValue(sensorOrientation) 
            ?? InputImageRotation.rotation90deg;

        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: defaultTargetPlatform == TargetPlatform.iOS 
                ? InputImageFormat.bgra8888 
                : InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
        
        final faces = await _faceDetector!.processImage(inputImage);
        
        if (mounted && !_isFaceDetected && faces.isNotEmpty) {
          _completeFaceScan(true);
        }
      } catch (e) {
        // Silently catch frame drops
      }
    });

    // 8-Second Timeout Fallback
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && !_isFaceDetected && _scanStatus == 0) {
        setState(() => _scanStatus = 2); 
        _cameraController?.stopImageStream();
      }
    });
  }

  Future<void> _completeFaceScan(bool success) async {
    if (_isFaceDetected) return; 
    if (mounted) {
      setState(() {
        _isFaceDetected = true;
        _scanStatus = 1;
      });
      _checkAnimController.forward();
    }
    try {
      await _cameraController?.stopImageStream();
    } catch (e) {
      debugPrint('Error stopping image stream: $e');
    } 
    
    await Future.delayed(const Duration(milliseconds: 2000));
    if (mounted) Navigator.pop(context, success);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 2),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    _checkAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 32),
              Text(
                _scanStatus == 0 ? "Verify Your Identity" : _scanStatus == 1 ? "Verification Successful" : "Verification Failed",
                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: _scanStatus == 2 ? Colors.redAccent : kTextDark),
              ),
              const SizedBox(height: 12),
              Text(
                _scanStatus == 0 ? "Position your face clearly in the frame" : _scanStatus == 1 ? "Your identity has been verified successfully" : "Could not verify your identity. Please try again.",
                style: GoogleFonts.inter(fontSize: 15, color: kTextMuted, height: 1.5), textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Container(
                height: 220, width: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _scanStatus == 0 ? kPrimaryGreen.withValues(alpha: 0.2) : _scanStatus == 1 ? kPrimaryGreen.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.1),
                      blurRadius: 30, spreadRadius: 8,
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _scanStatus == 0 ? kPrimaryGreen.withValues(alpha: 0.4) : _scanStatus == 1 ? kPrimaryGreen : Colors.redAccent, width: 3),
                    color: Colors.black.withValues(alpha: 0.02),
                  ),
                  child: _scanStatus == 0
                    ? (isDevMode 
                        ? const Center(child: Icon(Icons.developer_mode_rounded, size: 80, color: kPrimaryGreen))
                        : (_cameraInitialized && _cameraController != null && _cameraController!.value.isInitialized
                          ? ClipOval(child: CameraPreview(_cameraController!))
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(color: kPrimaryGreen, strokeWidth: 3),
                                  const SizedBox(height: 16),
                                  Text("Initializing...", style: GoogleFonts.inter(fontSize: 12, color: kTextMuted, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            )))
                    : Center(
                        child: _scanStatus == 1
                          ? ScaleTransition(
                              scale: _checkScaleAnimation,
                              child: Container(
                                width: 120, height: 120,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: kPrimaryGreen.withValues(alpha: 0.1)),
                                child: const Icon(Icons.check_circle_rounded, color: kPrimaryGreen, size: 100),
                              ),
                            )
                          : Container(
                              width: 120, height: 120,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent.withValues(alpha: 0.1)),
                              child: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 100),
                            ),
                      ),
                ),
              ),
              const SizedBox(height: 40),
              if (_scanStatus == 0)
                Column(
                  children: [
                    Text(isDevMode ? "Dev Mode Active..." : "Scanning...", style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kPrimaryGreen, letterSpacing: 0.5)),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: isDevMode ? null : (_detectionAttempts % 800) / 800,
                        minHeight: 4,
                        backgroundColor: Colors.black.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(kPrimaryGreen.withValues(alpha: 0.6)),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 32),
              if (_scanStatus == 0)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text("Cancel", style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                  ),
                )
              else if (_scanStatus == 2)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _scanStatus = 0);
                      _isFaceDetected = false;
                      _detectionAttempts = 0;
                      _checkAnimController.reset();
                      if (isDevMode) {
                        _simulateDevModeScan();
                      } else {
                        _initializeRealCamera();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text("Try Again", style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}