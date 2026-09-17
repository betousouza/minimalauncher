import 'package:flutter/material.dart';
import 'package:minimalauncher/data/jarvis_config.dart';
import 'package:minimalauncher/variables/strings.dart';

class JarvisSettingsPage extends StatefulWidget {
  const JarvisSettingsPage({super.key});

  @override
  State<JarvisSettingsPage> createState() => _JarvisSettingsPageState();
}

class _JarvisSettingsPageState extends State<JarvisSettingsPage> {
  final _serverUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _cfClientIdController = TextEditingController();
  final _cfClientSecretController = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await JarvisConfig.load();
    _serverUrlController.text = config.serverUrl;
    _apiKeyController.text = config.apiKey;
    _cfClientIdController.text = config.cfAccessClientId;
    _cfClientSecretController.text = config.cfAccessClientSecret;
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    await JarvisConfig.save(JarvisConfig(
      serverUrl: _serverUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      cfAccessClientId: _cfClientIdController.text.trim(),
      cfAccessClientSecret: _cfClientSecretController.text.trim(),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuração do Jarvis salva')),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _apiKeyController.dispose();
    _cfClientIdController.dispose();
    _cfClientSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jarvis', style: TextStyle(fontFamily: fontNormal)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Text(
                  'Endereço e credenciais do servidor do Jarvis, atravessando o '
                  'Cloudflare Access (ADR 0002). Modelo fixo: $jarvisModel.',
                  style: TextStyle(
                    fontFamily: fontNormal,
                    color: Colors.black.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16.0),
                _field('URL do servidor', _serverUrlController,
                    hint: 'https://jarvis.hcrs.com.br'),
                _field('Chave da API do OpenJarvis', _apiKeyController,
                    obscure: true),
                _field('CF-Access-Client-Id', _cfClientIdController,
                    obscure: true),
                _field('CF-Access-Client-Secret', _cfClientSecretController,
                    obscure: true),
                const SizedBox(height: 24.0),
                ElevatedButton(
                  onPressed: _save,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text('Salvar'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _field(String label, TextEditingController controller,
      {String? hint, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontFamily: fontNormal),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
