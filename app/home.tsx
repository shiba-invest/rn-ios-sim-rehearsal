import { StyleSheet, Text, View } from 'react-native';

export default function Home() {
  return (
    <View style={styles.root}>
      <Text style={styles.title}>ホーム</Text>
      <Text>The request reached the server and came back.</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, backgroundColor: '#fff' },
  title: { fontSize: 28 },
});
