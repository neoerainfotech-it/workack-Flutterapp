import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'constants.dart';
import 'api_constants.dart';

// --- DATA MODEL ---
class TimeLog {
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final int breakMinutes;

  TimeLog({required this.checkInTime, this.checkOutTime, this.breakMinutes = 0});

  // THE FIX: Automatically maps database keys (punch_in / punch_out) 
  // preventing the app from defaulting everything to DateTime.now()
  factory TimeLog.fromJson(Map<String, dynamic> json) {
    final rawIn = json['check_in_time'] ?? json['punch_in'] ?? json['date'];
    final rawOut = json['check_out_time'] ?? json['punch_out'];
    final rawBreak = json['break_minutes'] ?? json['total_break'] ?? 0;

    return TimeLog(
      checkInTime: rawIn != null ? DateTime.tryParse(rawIn.toString()) ?? DateTime.now() : DateTime.now(),
      checkOutTime: rawOut != null ? DateTime.tryParse(rawOut.toString()) : null,
      breakMinutes: int.tryParse(rawBreak.toString()) ?? 0,
    );
  }

  double get durationHours {
    if (checkOutTime == null) return 0;
    final minutes = checkOutTime!.difference(checkInTime).inMinutes - breakMinutes;
    return (minutes > 0 ? minutes : 0) / 60.0;
  }

  String get formattedDuration {
    if (checkOutTime == null) return "Active";
    final minutes = checkOutTime!.difference(checkInTime).inMinutes - breakMinutes;
    if (minutes <= 0) return "0h 0m";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return "${h}h ${m}m";
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime? _selectedFilterDate;
  List<TimeLog> _allLogs = [];
  List<TimeLog> _filteredLogs = [];
  
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchHistoryFromDatabase();
  }

  // --- FETCH FROM MYSQL ---
  Future<void> _fetchHistoryFromDatabase() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? empId = prefs.getString('emp_id');

      if (empId == null) {
        setState(() {
          _errorMessage = "Session expired. Please log out and log back in.";
          _isLoading = false;
        });
        return;
      }

      final response = await http.post(
        Uri.parse(ApiConstants.getHistory), 
        headers: {"Content-Type": "application/x-www-form-urlencoded"}, 
        body: { 'emp_id': empId },
      ).timeout(const Duration(seconds: 30)); 

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'success') {
          final List<dynamic> logsJson = data['data'] ?? [];
          setState(() {
            _allLogs = logsJson.map((json) => TimeLog.fromJson(json)).toList();
            
            // THE FIX: Ensure the newest records are ALWAYS at the top
            _allLogs.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
            
            _filteredLogs = List.from(_allLogs);
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = data['message'] ?? "Failed to load history.";
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = "Server error: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("🛑 HISTORY FETCH ERROR: $e"); 
      setState(() {
        _errorMessage = e.toString(); 
        _isLoading = false;
      });
    }
  }

  // --- FILTERING LOGIC ---
  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedFilterDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: kPrimaryGreen,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _errorMessage = null; 
        _selectedFilterDate = picked;
        _filteredLogs = _allLogs.where((log) {
          return log.checkInTime.year == picked.year &&
                 log.checkInTime.month == picked.month &&
                 log.checkInTime.day == picked.day;
        }).toList();
      });
    }
  }

  void _clearFilter() {
    setState(() {
      _selectedFilterDate = null;
      _filteredLogs = List.from(_allLogs);
    });
  }

  // --- STATS CALCULATION ---
  Map<String, dynamic> _calculateStats() {
    int daysPresent = _filteredLogs.length;
    double totalHours = _filteredLogs.fold(0, (sum, log) => sum + log.durationHours);
    double avgHours = daysPresent > 0 ? (totalHours / daysPresent) : 0;

    return {
      "days": daysPresent,
      "hours": totalHours.toStringAsFixed(1),
      "avg": avgHours.toStringAsFixed(1),
    };
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateStats();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: RefreshIndicator(
        color: kPrimaryGreen,
        onRefresh: _fetchHistoryFromDatabase,
        child: SafeArea(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              // --- HEADER ---
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: false,
                centerTitle: false,
                title: Text(
                  "Attendance History",
                  style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: kTextDark, letterSpacing: -0.5),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    
                    // --- STATS HORIZONTAL SCROLL ---
                    SizedBox(
                      height: 120,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _buildStatCard("Days Present", "${stats['days']}", _selectedFilterDate == null ? "All Time" : "Selected Day", const [Color(0xFFa18cd1), Color(0xFFfbc2eb)], Icons.event_available_rounded),
                          const SizedBox(width: 16),
                          _buildStatCard("Total Hours", "${stats['hours']}h", "Logged Time", const [Color(0xFF84fab0), Color(0xFF8fd3f4)], Icons.hourglass_bottom_rounded),
                          const SizedBox(width: 16),
                          _buildStatCard("Avg. Hours", "${stats['avg']}h", "Per Day", const [Color(0xFFf6d365), Color(0xFFfda085)], Icons.show_chart_rounded),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // --- CONTROLS ROW ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _selectedFilterDate != null ? kPrimaryGreen : Colors.black.withValues(alpha: 0.1)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.filter_alt_rounded, size: 18, color: _selectedFilterDate != null ? kPrimaryGreen : kTextMuted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedFilterDate != null ? DateFormat('MMM dd, yyyy').format(_selectedFilterDate!) : "All History",
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _selectedFilterDate != null ? kPrimaryGreen : kTextMuted),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (_selectedFilterDate != null)
                                    GestureDetector(
                                      onTap: _clearFilter,
                                      child: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                                    )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),

              // --- HISTORY LOG CARDS ---
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                sliver: _buildListContent(),
              ),
              
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  // --- STATE HANDLERS FOR THE LIST ---
  Widget _buildListContent() {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 40.0),
          child: Center(child: CircularProgressIndicator(color: kPrimaryGreen)),
        ),
      );
    }

    if (_errorMessage != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Center(
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded, size: 60, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(_errorMessage!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    if (_filteredLogs.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Center(
            child: Column(
              children: [
                const Icon(Icons.history_rounded, size: 60, color: Colors.black12),
                const SizedBox(height: 16),
                Text("No records found.", style: GoogleFonts.inter(color: kTextMuted, fontSize: 16)),
              ],
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return _buildHistoryCard(_filteredLogs[index]);
        },
        childCount: _filteredLogs.length,
      ),
    );
  }

  // =========================================================================
  // WIDGET BUILDERS
  // =========================================================================
  
  Widget _buildStatCard(String title, String value, String subtitle, List<Color> gradient, IconData icon) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const Spacer(),
          Text(value, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: kTextDark)),
          Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kTextMuted)),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(TimeLog log) {
    bool isActive = log.checkOutTime == null;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMM dd, yyyy').format(log.checkInTime),
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: kTextDark),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF0984e3).withValues(alpha: 0.1) : const Color(0xFF00b894).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isActive ? "Active Now" : "Completed",
                  style: GoogleFonts.inter(
                    fontSize: 11, 
                    fontWeight: FontWeight.w700, 
                    color: isActive ? const Color(0xFF0984e3) : const Color(0xFF00b894),
                  ),
                ),
              )
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(height: 1, thickness: 1),
          ),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.login_rounded, size: 14, color: kTextMuted),
                      const SizedBox(width: 4),
                      Text("Check In", style: GoogleFonts.inter(fontSize: 12, color: kTextMuted, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(DateFormat('hh:mm a').format(log.checkInTime), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kTextDark)),
                ],
              ),
              
              const Icon(Icons.arrow_forward_rounded, color: Colors.black12, size: 20),
              
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.logout_rounded, size: 14, color: kTextMuted),
                      const SizedBox(width: 4),
                      Text("Check Out", style: GoogleFonts.inter(fontSize: 12, color: kTextMuted, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(log.checkOutTime != null ? DateFormat('hh:mm a').format(log.checkOutTime!) : "--:--", style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kTextDark)),
                ],
              ),
              
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text("Total", style: GoogleFonts.inter(fontSize: 10, color: kTextMuted, fontWeight: FontWeight.w600)),
                    Text(log.formattedDuration, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: kPrimaryGreen)),
                  ],
                ),
              )
            ],
          ),
        ],
      ),
    );
  }
}