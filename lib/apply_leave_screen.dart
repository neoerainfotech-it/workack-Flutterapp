import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'api_constants.dart';

class ApplyLeaveScreen extends StatefulWidget {
  const ApplyLeaveScreen({super.key});

  @override
  State<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends State<ApplyLeaveScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Form State
  String? _selectedLeaveType;
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _reasonController = TextEditingController();
  
  // Logic State
  int _calculatedDays = 0;
  bool _isDateError = false;
  bool _isSubmitting = false;
  
  // 👇 THE FIX: Dynamic Leave Balances 👇
  int _allocatedLeaves = 12; // Total given by admin (Default 12)
  int _usedLeaves = 0;       // Calculated from history
  int _remainingLeaveBalance = 12; 
  int _unpaidLeaves = 0;

  List<dynamic> _leaveHistory = [];
  bool _isLoadingHistory = true;

  Timer? _backgroundRefreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchLeaveHistory(); // Initial loud load
    
    // 👇 2. Start checking the server quietly every 10 seconds
    _backgroundRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _fetchLeaveHistory(isSilent: true); 
      }
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _backgroundRefreshTimer?.cancel(); // 👇 3. Stop the timer when leaving the screen!
    super.dispose();
  }

  // --- LOGIC: Date Calculation ---
  void _calculateDays() {
    if (_startDate != null && _endDate != null) {
      if (_endDate!.isBefore(_startDate!)) {
        setState(() {
          _isDateError = true;
          _calculatedDays = 0;
        });
      } else {
        setState(() {
          _isDateError = false;
          _calculatedDays = _endDate!.difference(_startDate!).inDays + 1; 
        });
      }
    } else {
      setState(() {
        _isDateError = false;
        _calculatedDays = 0;
      });
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime.now().subtract(const Duration(days: 30)), 
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: kPrimaryGreen, onPrimary: Colors.white, onSurface: Colors.black),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
        }
      });
      _calculateDays();
    }
  }

  // --- LOGIC: Real Submission to MySQL ---
  Future<void> _submitRequest() async {
    if (_formKey.currentState!.validate()) {
      if (_isDateError || _calculatedDays <= 0) {
        _showSnackBar("Please select a valid date range.", isError: true);
        return;
      }
      
      

      setState(() => _isSubmitting = true);
      
      try {
        final prefs = await SharedPreferences.getInstance();
        final String? empId = prefs.getString('emp_id');

        if (empId == null) {
          _showSnackBar("Session expired. Please log in again.", isError: true);
          setState(() => _isSubmitting = false);
          return;
        }

        final String formattedStart = DateFormat('yyyy-MM-dd').format(_startDate!);
        final String formattedEnd = DateFormat('yyyy-MM-dd').format(_endDate!);

        final response = await http.post(
          Uri.parse(ApiConstants.applyLeave),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            'emp_id': empId,
            'leave_type': _selectedLeaveType!,
            'start_date': formattedStart,
            'end_date': formattedEnd,
            'total_days': _calculatedDays.toString(),
            'reason': _reasonController.text.trim(),
          },
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'success') {
            _showSnackBar("Leave request submitted successfully! Awaiting Admin approval.", isError: false);
            _resetForm();
            _fetchLeaveHistory(); // Instantly fetch history to reduce balance UI!
          } else {
            _showSnackBar(data['message'] ?? "Failed to submit request.", isError: true);
          }
        } else {
          _showSnackBar("Server error. Please try again later.", isError: true);
        }
      } catch (e) {
        debugPrint("🛑 Leave Submission Error: $e");
        _showSnackBar("Network error. Please check your connection.", isError: true);
      } finally {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
      }
    }
  }

  // 👇 4. Add the 'isSilent' parameter
  Future<void> _fetchLeaveHistory({bool isSilent = false}) async {
    // Only show the loading spinner if it is NOT a silent background refresh
    if (!isSilent) {
      setState(() => _isLoadingHistory = true);
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? empId = prefs.getString('emp_id');

      if (empId == null) {
        if (!isSilent) setState(() => _isLoadingHistory = false);
        return;
      }

      final response = await http.post(
        Uri.parse(ApiConstants.getLeaveHistory), 
        headers: {"Content-Type": "application/x-www-form-urlencoded"}, 
        body: {
          'emp_id': empId 
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _leaveHistory = data['data'];
            
            // Automatically Calculate Remaining Leaves
            _allocatedLeaves = data['allocated_leaves'] ?? 12; 
            
            _usedLeaves = 0;
            for (var leave in _leaveHistory) {
              String status = (leave['status'] ?? '').toString().toLowerCase();
              if (status != 'rejected') {
                _usedLeaves += int.tryParse(leave['total_days'].toString()) ?? 0;
              }
            }
            
            // 👇 ENTERPRISE MATH FIX 👇
            _remainingLeaveBalance = _allocatedLeaves - _usedLeaves;
            
            if (_remainingLeaveBalance < 0) {
              // If it's negative, convert the negative number to a positive Unpaid count!
              _unpaidLeaves = _remainingLeaveBalance.abs(); 
              _remainingLeaveBalance = 0; // Lock paid balance at 0
            } else {
              _unpaidLeaves = 0;
            }
          });
        } else {
          if (!isSilent) _showSnackBar("History Error: ${data['message']}", isError: true);
        }
      } else {
        if (!isSilent) _showSnackBar("Server Error: ${response.statusCode}", isError: true);
      }
    } catch (e) {
      debugPrint("Error fetching leave history: $e");
      if (!isSilent) _showSnackBar("Failed to load history. Check your internet.", isError: true);
    } finally {
      if (mounted && !isSilent) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  void _resetForm() {
    setState(() {
      _selectedLeaveType = null;
      _startDate = null;
      _endDate = null;
      _calculatedDays = 0;
      _isDateError = false;
      _reasonController.clear();
      _formKey.currentState?.reset();
    });
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: isError ? Colors.redAccent : kPrimaryGreen,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // --- HEADER ---
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              pinned: false,
              title: Text("Leave Application", style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: kTextDark, letterSpacing: -0.5)),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 800) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2, 
                              child: Column(
                                children: [
                                  _buildFormCard(),
                                  const SizedBox(height: 32),
                                  _buildHistorySection(), 
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(flex: 1, child: _buildBalanceCard()),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            _buildBalanceCard(),
                            const SizedBox(height: 24),
                            _buildFormCard(),
                            const SizedBox(height: 32),
                            _buildHistorySection(),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 100), // Navigation Bar Padding
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // WIDGET: BALANCE CARD
  // =========================================================================
  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.scale_rounded, color: kPrimaryGreen, size: 20),
              const SizedBox(width: 8),
              Text("Your Balance", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kTextDark)),
            ],
          ),
          const SizedBox(height: 4),
          Text("Annual Paid Leave", style: GoogleFonts.inter(fontSize: 13, color: kTextMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 32),
          
          // Circular Balance Indicator
          // Circular Balance Indicator
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: _allocatedLeaves > 0 ? _remainingLeaveBalance / _allocatedLeaves : 0, 
                  strokeWidth: 8,
                  backgroundColor: kPrimaryGreen.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryGreen),
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("$_remainingLeaveBalance", style: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w800, color: kTextDark, height: 1.0)),
                      const SizedBox(height: 4),
                      Text("out of $_allocatedLeaves", style: GoogleFonts.inter(fontSize: 11, color: kTextMuted, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // 👇 NEW: UNPAID LEAVE TRACKER BADGE 👇
          if (_unpaidLeaves > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Text(
                "$_unpaidLeaves Unpaid Day(s) Taken (LOP)",
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
              ),
            ),
          ],
          // 👆 END NEW BADGE 👆
          
          const SizedBox(height: 32),
          
          // Policy Note
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(16), border: const Border(left: BorderSide(color: kPrimaryGreen, width: 4))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Policy Note:", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: kTextDark)),
                const SizedBox(height: 8),
                _buildPolicyBullet("Sick leave requires a certificate if exceeding 2 days."),
                const SizedBox(height: 4),
                _buildPolicyBullet("Annual leave must be applied 1 week in advance."),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPolicyBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 6.0, right: 8.0), child: CircleAvatar(radius: 3, backgroundColor: kTextMuted)),
        Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: kTextMuted, height: 1.5))),
      ],
    );
  }

  // =========================================================================
  // WIDGET: LEAVE FORM CARD
  // =========================================================================
  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: kPrimaryGreen, size: 22),
                const SizedBox(width: 8),
                Text("New Request", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kTextDark)),
              ],
            ),
            const SizedBox(height: 24),

            // Leave Type
            _buildLabel("Leave Type"),
            DropdownButtonFormField<String>(
              initialValue: _selectedLeaveType, 
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kPrimaryGreen),
              style: GoogleFonts.inter(fontSize: 14, color: kTextDark, fontWeight: FontWeight.w600),
              decoration: _inputDecoration(hint: "Select Type"),
              items: const [
                DropdownMenuItem(value: "annual", child: Text("Annual Leave (PTO)")),
                DropdownMenuItem(value: "sick", child: Text("Sick Leave")),
                DropdownMenuItem(value: "emergency", child: Text("Emergency Leave")),
                DropdownMenuItem(value: "wfh", child: Text("Work From Home Request")),
              ],
              onChanged: (val) => setState(() => _selectedLeaveType = val),
              validator: (val) => val == null ? "Please select a leave type" : null,
            ),
            const SizedBox(height: 20),

            // Date Range
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("Start Date"),
                      GestureDetector(
                        onTap: () => _selectDate(context, true),
                        child: AbsorbPointer(
                          child: TextFormField(
                            key: ValueKey(_startDate),
                            initialValue: _startDate != null ? DateFormat('MMM dd, yyyy').format(_startDate!) : "",
                            style: GoogleFonts.inter(fontSize: 14, color: kTextDark, fontWeight: FontWeight.w600),
                            decoration: _inputDecoration(hint: "Select Start", icon: Icons.date_range_rounded),
                            validator: (_) => _startDate == null ? "Required" : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("End Date"),
                      GestureDetector(
                        onTap: () => _selectDate(context, false),
                        child: AbsorbPointer(
                          child: TextFormField(
                            key: ValueKey(_endDate),
                            initialValue: _endDate != null ? DateFormat('MMM dd, yyyy').format(_endDate!) : "",
                            style: GoogleFonts.inter(fontSize: 14, color: kTextDark, fontWeight: FontWeight.w600),
                            decoration: _inputDecoration(hint: "Select End", icon: Icons.event_rounded),
                            validator: (_) => _endDate == null ? "Required" : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Calculated Duration
            _buildLabel("Calculated Duration"),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: _isDateError ? Colors.redAccent.withValues(alpha: 0.1) : kPrimaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _isDateError ? Colors.redAccent.withValues(alpha: 0.3) : Colors.transparent),
              ),
              child: Text(
                _isDateError ? "Invalid Range" : "$_calculatedDays Day${_calculatedDays == 1 ? '' : 's'}",
                style: GoogleFonts.inter(
                  fontSize: 15, 
                  fontWeight: FontWeight.bold, 
                  color: _isDateError ? Colors.redAccent : kPrimaryGreen
                ),
              ),
            ),
            
            // 👇 ENTERPRISE FIX: Show LOP (Loss of Pay) Warning if they exceed their balance 👇
            if (!_isDateError && _calculatedDays > _remainingLeaveBalance)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "You only have $_remainingLeaveBalance paid day(s) left. ${ _calculatedDays - _remainingLeaveBalance } day(s) will be marked as Unpaid Leave (Loss of Pay).",
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w600, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            // 👆 END ENTERPRISE FIX 👆
            
            const SizedBox(height: 20),

            // Reason
            _buildLabel("Reason for Leave"),
            TextFormField(
              controller: _reasonController,
              maxLines: 4,
              style: GoogleFonts.inter(fontSize: 14, color: kTextDark, fontWeight: FontWeight.w500),
              decoration: _inputDecoration(hint: "Briefly describe why you are requesting leave..."),
              validator: (val) => val == null || val.trim().isEmpty ? "Please provide a reason" : null,
            ),
            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : _resetForm,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Colors.redAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text("Clear Form", style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitRequest,
                    icon: _isSubmitting 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    label: Text(_isSubmitting ? "Submitting..." : "Submit Request", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // --- FORM HELPERS ---
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: kTextMuted, letterSpacing: 0.5)),
    );
  }

  InputDecoration _inputDecoration({required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.black.withValues(alpha: 0.2)),
      prefixIcon: icon != null ? Icon(icon, size: 20, color: kPrimaryGreen) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimaryGreen, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5))),
    );
  }

  // =========================================================================
  // WIDGET: LEAVE HISTORY SECTION
  // =========================================================================
  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Your Leave History", 
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kTextDark)
        ),
        const SizedBox(height: 16),
        
        if (_isLoadingHistory)
          const Center(child: CircularProgressIndicator(color: kPrimaryGreen))
        else if (_leaveHistory.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16)),
            child: Text("No leave history found.", textAlign: TextAlign.center, style: GoogleFonts.inter(color: kTextMuted)),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(), // Let the CustomScrollView handle scrolling
            itemCount: _leaveHistory.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = _leaveHistory[index];
              
              // Define Status Colors
              Color statusColor;
              Color statusBg;
              String status = item['status'] ?? 'Pending';
              
              if (status.toLowerCase() == 'approved') {
                statusColor = Colors.green;
                statusBg = Colors.green.withValues(alpha: 0.1);
                
              // 👇 Added 'not approved' so it turns Red instead of Orange!
              } else if (status.toLowerCase() == 'rejected' || status.toLowerCase() == 'not approved') {
                statusColor = Colors.redAccent;
                statusBg = Colors.redAccent.withValues(alpha: 0.1);
              } else {
                statusColor = Colors.orange;
                statusBg = Colors.orange.withValues(alpha: 0.1);
              }

              // Format Dates beautifully
              DateTime start = DateTime.parse(item['start_date']);
              DateTime end = DateTime.parse(item['end_date']);
              String dateText = start == end 
                  ? DateFormat('MMM dd, yyyy').format(start)
                  : "${DateFormat('MMM dd').format(start)} - ${DateFormat('MMM dd, yyyy').format(end)}";

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    // Icon Left
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: kPrimaryGreen.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.event_note_rounded, color: kPrimaryGreen),
                    ),
                    const SizedBox(width: 16),
                    
                    // Details Middle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item['leave_type'] ?? 'Leave').toString().toUpperCase(), 
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: kTextMuted)
                          ),
                          const SizedBox(height: 4),
                          Text(dateText, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kTextDark)),
                        ],
                      ),
                    ),

                    // Status Right
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${item['total_days']} Day${item['total_days'] == '1' ? '' : 's'}", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: kTextDark)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            status.toUpperCase(), 
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)
                          ),
                        )
                      ],
                    )
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}