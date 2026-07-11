import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gal/gal.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:file_saver/file_saver.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.storage.request();
  runApp(
    MaterialApp(
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const TranscriptApp(),
    ),
  );
}

class TranscriptApp extends StatefulWidget {
  const TranscriptApp({super.key});

  @override
  State<TranscriptApp> createState() => _TranscriptAppState();
}

class _TranscriptAppState extends State<TranscriptApp> {
  InAppWebViewController? _webViewController;
  bool _isDownloading = false;
  double _loadingProgress = 0.0;
  
  List<Uint8List> _extractedPages = [];
  int _expectedPagesCount = 0;

  final String _extractorScript = """
    (function() {
      const canvases = document.querySelectorAll('canvas');
      if(canvases.length === 0) {
        window.flutter_inappwebview.callHandler('notifyError', 'No document pages found on screen. Ensure you are on the transcript page.');
        return;
      }
      window.flutter_inappwebview.callHandler('startExtraction', canvases.length);
      canvases.forEach((canvas, index) => {
        try {
          const dataUrl = canvas.toDataURL('image/png');
          window.flutter_inappwebview.callHandler('processPage', dataUrl, index, canvases.length);
        } catch(e) {
          window.flutter_inappwebview.callHandler('notifyError', 'Canvas is protected or cross-origin restricted.');
        }
      });
    })();
  """;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcript Download', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Page',
            onPressed: () => _webViewController?.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("https://studentportal.egerton.ac.ke/"),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              clearCache: true,
              userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
              allowUniversalAccessFromFileURLs: true,
              allowFileAccessFromFileURLs: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              thirdPartyCookiesEnabled: true,
            ),
            onReceivedServerTrustAuthRequest: (controller, challenge) async {
              return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
            },
            onWebViewCreated: (controller) => _setupWebviewHandlers(controller),
            onProgressChanged: (controller, progress) {
              setState(() => _loadingProgress = progress / 100);
            },
          ),
          if (_loadingProgress < 1.0)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        value: _loadingProgress > 0 ? _loadingProgress : null,
                        strokeWidth: 4,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Loading Portal... ${(_loadingProgress * 100).toInt()}%',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isDownloading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 4),
                          SizedBox(height: 20),
                          Text('Getting pages...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download Transcript', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: _isDownloading ? null : _triggerExtraction,
          ),
        ),
      ),
    );
  }

  void _setupWebviewHandlers(InAppWebViewController controller) {
    _webViewController = controller;

    controller.addJavaScriptHandler(
      handlerName: 'startExtraction',
      callback: (args) {
        _expectedPagesCount = args[0];
        _extractedPages = [];
      }
    );

    controller.addJavaScriptHandler(
      handlerName: 'processPage',
      callback: (args) async {
        final String base64Stream = args[0];

        try {
          final String pureBase64 = base64Stream.split(',')[1];
          final Uint8List binaryData = base64Decode(pureBase64);
          
          _extractedPages.add(binaryData);
          
          if (_extractedPages.length == _expectedPagesCount) {
            _toggleLoading(false);
            _showSelectionDialog(_extractedPages);
          }
        } catch (e) {
          _toggleLoading(false);
          _showFeedback("Error reading page data: $e");
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'notifyError',
      callback: (args) {
        _toggleLoading(false);
        _showFeedback(args[0].toString());
      },
    );
  }

  void _triggerExtraction() {
    _toggleLoading(true);
    _webViewController?.evaluateJavascript(source: _extractorScript);
  }

  void _toggleLoading(bool value) => setState(() => _isDownloading = value);

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSelectionDialog(List<Uint8List> pages) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return PageSelectionSheet(pages: pages);
      },
    );
  }
}

class PageSelectionSheet extends StatefulWidget {
  final List<Uint8List> pages;

  const PageSelectionSheet({super.key, required this.pages});

  @override
  State<PageSelectionSheet> createState() => _PageSelectionSheetState();
}

class _PageSelectionSheetState extends State<PageSelectionSheet> {
  late List<bool> _selectedPages;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _selectedPages = List.filled(widget.pages.length, true);
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveAsImages() async {
    setState(() => _isProcessing = true);
    try {
      int savedCount = 0;
      for (int i = 0; i < widget.pages.length; i++) {
        if (_selectedPages[i]) {
          await Gal.putImageBytes(widget.pages[i]);
          savedCount++;
        }
      }
      _showFeedback("Successfully saved $savedCount images to gallery!");
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showFeedback("Error saving images: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveAsPdf() async {
    setState(() => _isProcessing = true);
    try {
      final pdf = pw.Document();
      
      for (int i = 0; i < widget.pages.length; i++) {
        if (_selectedPages[i]) {
          final image = pw.MemoryImage(widget.pages[i]);
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(image.width!.toDouble(), image.height!.toDouble()),
              margin: pw.EdgeInsets.zero,
              build: (pw.Context context) {
                return pw.Image(image, fit: pw.BoxFit.contain);
              },
            ),
          );
        }
      }

      final pdfBytes = await pdf.save();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = "transcript_$timestamp";

      final String? path = await FileSaver.instance.saveAs(
        name: fileName,
        bytes: pdfBytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );

      if (path != null && path.isNotEmpty) {
        _showFeedback("Saved PDF to $path");
      } else {
        _showFeedback("PDF save cancelled or failed.");
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showFeedback("Error saving PDF: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16.0, left: 8.0),
            child: Text(
              'Select Pages to Download',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.pages.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: CheckboxListTile(
                    title: Text('Page ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('e.g., Year ${index + 1}'),
                    value: _selectedPages[index],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onChanged: (bool? value) {
                      setState(() {
                        _selectedPages[index] = value ?? false;
                      });
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (_isProcessing)
            const Center(child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ))
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('As Images'),
                    onPressed: _selectedPages.contains(true) ? _saveAsImages : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('As PDF'),
                    onPressed: _selectedPages.contains(true) ? _saveAsPdf : null,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
